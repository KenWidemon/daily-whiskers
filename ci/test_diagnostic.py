"""Pure fixtures/mocks only. Never boots, builds, runs, or samples an app."""
import copy
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import diagnostic as d
import diagnostic_monitor as monitor
import diagnostic_results as evidence
import simulator

ROOT = Path(__file__).resolve().parent.parent
UUID = '11111111-1111-4111-8111-111111111111'
SELECTOR = d.LANES['cards'][0][1]
ENV = {'SOURCE_SHA': 'a' * 40, 'TESTED_SHA': 'a' * 40, 'GITHUB_SHA': 'a' * 40,
       'GITHUB_RUN_ID': '12', 'GITHUB_RUN_ATTEMPT': '1', 'GITHUB_JOB': 'diagnostic',
       'CI_SHARD_ID': 'cards', 'CI_DIAGNOSTIC_LANE': 'cards'}


def summary():
    counts = {'passedTests': 1, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}
    return dict(counts, totalTestCount=1, result='Passed', devicesAndConfigurations=[dict(counts, device={
        'deviceName': simulator.NAME, 'modelName': simulator.NAME, 'osVersion': simulator.VERSION,
        'osBuildNumber': simulator.BUILD, 'architecture': 'arm64', 'platform': 'iOS Simulator', 'deviceId': UUID})])


def tree():
    return {'testNodes': [{'nodeType': 'Test Case', 'result': 'Passed',
                          'nodeIdentifier': '/'.join(SELECTOR.split('/')[1:]) + '()',
                          'nodeIdentifierURL': 'test://' + SELECTOR}]}


def marker_rows():
    method = SELECTOR.split('/')[-1]
    base = {'schema_version': 1, 'session_id': UUID, 'pid': 123, 'runner_bundle_id': 'runner.bundle',
            'container_home': '/owned', 'test': f'-[DailyWhiskersUITests.SavedCardsTests {method}]',
            'stream': 'cards', 'process_name': 'Runner', 'record_complete': True, 'dropped_event_count': 0,
            'fields_truncated': False, 'export_error': None, 'event_wall_time': 10.0, 'export_wall_time': 10.1,
            'event_monotonic_ns': '100', 'export_monotonic_ns': '101'}
    return [dict(base, sequence=i, phase=phase, edge=edge, operation_id=operation, terminal=i == 4,
                 stream_complete=i == 4) for i, (phase, edge, operation) in enumerate([
                     ('test', 'enter', ''), ('app_termination', 'enter', 'operation'),
                     ('app_termination', 'return', 'operation'), ('test', 'return', '')], 1)]


class DiagnosticTests(unittest.TestCase):
    def test_exact_five_methods_and_lane_order(self):
        self.assertEqual(list(d.LANES), ['visual', 'startup-reminder', 'cards'])
        self.assertEqual([stage for pairs in d.LANES.values() for stage, _ in pairs],
                         ['visual', 'startup', 'reminder', 'cards-largest', 'cards-adaptive'])
        self.assertEqual(len({selector for pairs in d.LANES.values() for _, selector in pairs}), 5)

    def test_only_ui_options_add_diagnostic_flags_and_method_allowances(self):
        with patch.object(d, 'common', return_value=[]), patch.object(d, 'owned', return_value={'simulator_id': UUID}):
            visual = d.test_options('visual')
            self.assertIn('DailyWhiskers', visual)
            self.assertFalse(any('CI_SMOKE_TESTING' in option for option in visual))
            self.assertNotIn('-test-timeouts-enabled', visual)
            self.assertNotIn('-default-test-execution-time-allowance', visual)
            self.assertNotIn('-maximum-test-execution-time-allowance', visual)
            for lane in ('cards', 'startup-reminder'):
                options = d.test_options(lane)
                self.assertIn('DailyWhiskersInteraction', options)
                self.assertIn('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING CI_DIAGNOSTIC_TESTING', options)
                self.assertEqual(options[options.index('-default-test-execution-time-allowance') + 1], '720')
                self.assertEqual(options[options.index('-maximum-test-execution-time-allowance') + 1], '720')
                self.assertNotIn('-retry-tests-on-failure', options)

    def test_disposable_workflow_is_not_acceptance(self):
        text = (ROOT / '.github/workflows/ios.yml').read_text()
        self.assertIn('  workflow_dispatch:', text)
        self.assertNotIn('  pull_request:', text)
        self.assertNotIn('  push:', text)
        self.assertNotIn('name: CI Gate', text)
        self.assertNotIn('actions/cache', text)
        self.assertIn('fail-fast: false', text)
        self.assertIn('timeout-minutes: 60', text)
        self.assertEqual(text.count('run-stage.py init-budget 2700'), 1)
        self.assertIn("matrix.second != '' && steps.first.outcome == 'success'", text)
        self.assertIn("github.run_attempt == 1", text)
        self.assertIn('expected_source_sha:', text)
        self.assertIn('build/Diagnostic-*.xcresult', text)
        self.assertIn('retention-days: 30', text)
        self.assertIn('include-hidden-files: true', text)
        upload = text.split('name: Upload all raw diagnostic evidence', 1)[1]
        self.assertIn('timeout-minutes: 5', upload)
        self.assertLess(text.index('diagnostic.py export'), text.index('simulator.py cleanup'))
        self.assertNotIn('policy.py gate', text)

    def test_workflow_builds_before_one_boot_under_original_budget(self):
        text = (ROOT / '.github/workflows/ios.yml').read_text()
        steps = re.split(r'^      - ', text, flags=re.M)[1:]
        commands = []
        for step in steps[:10]:
            run = re.search(r'^        run: (.+)$', step, re.M)
            commands.append(run[1] if run else step.splitlines()[0].split('@', 1)[0])
        selected = 'python3 ci/run-stage.py "$DIAGNOSTIC_STAGE" python3 ci/diagnostic.py test --stage "$DIAGNOSTIC_STAGE"'
        self.assertEqual(commands, [
            'uses: actions/checkout', '|',
            'python3 ci/run-stage.py init-budget 2700',
            'python3 ci/run-stage.py prepare bash ci/prepare-app.sh',
            'python3 ci/run-stage.py diagnostic-preflight python3 ci/diagnostic.py preflight',
            'python3 ci/run-stage.py resolve bash ci/test-app.sh resolve',
            'python3 ci/run-stage.py diagnostic-build python3 ci/diagnostic.py build',
            'python3 ci/run-stage.py boot python3 ci/diagnostic.py boot',
            selected, selected])
        self.assertIn('ref: ${{ github.sha }}', steps[0])
        self.assertIn('test "$GITHUB_SHA" = "$EXPECTED_SOURCE_SHA"', steps[1])
        self.assertIn('test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"', steps[1])
        self.assertIn('echo "TESTED_SHA=$(git rev-parse HEAD)" >> "$GITHUB_ENV"', steps[1])
        self.assertEqual(text.count('init-budget'), 1)
        self.assertEqual(text.count('diagnostic.py boot'), 1)
        self.assertNotIn('CI_EXECUTION_DEADLINE', text)  # No per-stage deadline reset.

    def test_identity_rejects_missing_or_cross_source_lane(self):
        with patch.dict(os.environ, ENV, clear=True):
            self.assertEqual(d.identity()['lane'], 'cards')
            for key, value in [('GITHUB_JOB', 'ui-shards'), ('TESTED_SHA', 'b' * 40), ('CI_SHARD_ID', 'settings'), ('GITHUB_RUN_ID', '')]:
                with self.subTest(key=key), patch.dict(os.environ, {key: value}):
                    self.assertRaises(ValueError, d.identity)

    def test_readiness_caps_remaining_budget_without_simctl_wrapper(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(d, 'DIAGNOSTIC', Path(temporary)), patch.object(d, 'identity', return_value={}), \
                 patch.object(d, 'owned', return_value={'simulator_id': UUID}), \
                 patch.object(d, 'deadline', return_value=110), patch.object(d.time, 'time', return_value=100), \
                 patch.object(d.simulator, 'exact_device', side_effect=[{'state': 'Shutdown'}, {'state': 'Booted'}]), \
                 patch.object(d, 'run_output', side_effect=['simctl boot <device>', 'simctl bootstatus <device>',
                     'simctl get_app_container <device>', '{}', '', 'ready', '{}']) as command:
                d.boot()
                calls = command.call_args_list
                readiness = next(call for call in calls if call.args[0][2] == 'bootstatus')
                self.assertEqual(readiness.kwargs, {'seconds': 300, 'until': 110})
                self.assertTrue(all(call.kwargs['until'] == 110 for call in calls))

    def test_readiness_rejects_preexisting_or_mismatched_ownership(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(d, 'BUILD', Path(temporary)), patch.dict(os.environ, ENV | {'SIMULATOR_ID': UUID}):
            record = simulator.identity() | {'status': 'ready', 'readback_verified': True, 'ownership': 'preexisting', 'simulator_id': UUID}
            (Path(temporary) / 'simulator.json').write_text(json.dumps(record))
            self.assertRaises(ValueError, d.owned)

    def test_command_timeout_respects_shared_deadline(self):
        with patch.object(d.time, 'time', return_value=100), patch.object(d.subprocess, 'check_output', return_value='ok') as run:
            self.assertEqual(d.run_output(['helper'], seconds=300, until=103), 'ok')
            self.assertEqual(run.call_args.kwargs['timeout'], 3)
            self.assertRaises(ValueError, d.run_output, ['helper'], until=99)
            self.assertEqual(run.call_count, 1)

    def test_selected_case_requires_exact_target_destination_and_single_execution(self):
        self.assertEqual(evidence.validate_selected(summary(), tree(), SELECTOR, UUID), SELECTOR)
        mutations = [lambda s, t: s.update(skippedTests=1, passedTests=0),
                     lambda s, t: t['testNodes'].append(copy.deepcopy(t['testNodes'][0])),
                     lambda s, t: t['testNodes'][0].update(nodeIdentifierURL='test://Other/' + SELECTOR.split('/', 1)[1]),
                     lambda s, t: s['devicesAndConfigurations'][0]['device'].update(deviceId='wrong'),
                     lambda s, t: s['devicesAndConfigurations'][0].update(passedTests=2)]
        for mutate in mutations:
            s, t = summary(), tree()
            mutate(s, t)
            self.assertRaises(ValueError, evidence.validate_selected, s, t, SELECTOR, UUID)

    def test_exact_xctest_name_normalization(self):
        name = marker_rows()[0]['test']
        self.assertTrue(monitor.normalize_test_name(name, SELECTOR))
        for wrong in [name.replace('SavedCardsTests', 'Other'), name.replace('DailyWhiskersUITests', 'Other'), name + 'Suffix', name.replace('testLargest', 'testOtherLargest')]:
            self.assertFalse(monitor.normalize_test_name(wrong, SELECTOR))

    def validate_rows(self, rows, suffix='\n'):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'markers.jsonl'
            path.write_text('\n'.join(json.dumps(row) for row in rows) + suffix)
            report = {'runner_pid': 123, 'stage': 'cards-largest', 'runner_data_container': '/owned'}
            metadata = {'lane': 'cards', 'bundles': {'runner': {'bundle_id': 'runner.bundle'}}}
            return evidence.validate_markers([path], SELECTOR, report, metadata)

    def test_marker_complete_transport(self):
        self.assertEqual(self.validate_rows(marker_rows())['events'], 4)

    def test_marker_incomplete_identity_and_pairing_fail_closed(self):
        mutations = [lambda rows: rows[1].update(fields_truncated=True),
                     lambda rows: rows[1].update(sequence=4),
                     lambda rows: rows[1].update(pid=99),
                     lambda rows: rows[1].update(container_home='/foreign'),
                     lambda rows: rows[2].update(operation_id='wrong'),
                     lambda rows: rows[-1].update(stream_complete=False),
                     lambda rows: rows[1].update(dropped_event_count=1),
                     lambda rows: rows[0].update(phase='other')]
        for mutate in mutations:
            rows = marker_rows()
            mutate(rows)
            self.assertRaises(ValueError, self.validate_rows, rows)
        self.assertRaises(ValueError, self.validate_rows, marker_rows(), '')

    def test_only_exact_owned_runner_is_discovered(self):
        with patch.object(d, 'run_output', return_value='10 /other/Runner\n11 /owned/Runner'):
            self.assertEqual(monitor.discover_runner(Path('/owned/Runner'), 123), 11)
        with patch.object(d, 'run_output', return_value='11 /owned/Runner\n12 /owned/Runner'):
            self.assertRaises(ValueError, monitor.discover_runner, Path('/owned/Runner'), 123)

    def test_monitor_helper_budget_and_unchanged_write_suppression(self):
        with patch.object(monitor, '_helper_calls', monitor.MAX_HELPER_CALLS), patch.object(d, 'run_output') as command:
            self.assertRaises(ValueError, monitor.host_output, ['helper'])
            command.assert_not_called()
        with tempfile.TemporaryDirectory() as temporary, patch.object(d, 'DIAGNOSTIC', Path(temporary)), patch.dict(os.environ, ENV):
            process = Mock(pid=42)
            instance = monitor.Monitor('cards', 'cards-largest', process, {'lane': 'cards'}, 99999999999)
            with patch.object(d, 'write') as write:
                instance.write()
                instance.write()
                write.assert_not_called()
                instance.report['errors'].append('changed')
                instance.write()
                self.assertEqual(write.call_count, 1)
            instance.discovery_attempts = 60
            self.assertRaises(ValueError, instance.discover)

    def test_startup_window_uses_original_deadline_and_preserves_started_method(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(d, 'DIAGNOSTIC', Path(temporary)), patch.dict(os.environ, ENV):
            instance = monitor.Monitor('cards', 'cards-largest', Mock(pid=42), {'lane': 'cards'}, 1000, started=100)
            self.assertEqual(instance.startup_until, 400)
            with patch.object(monitor.time, 'time', return_value=400):
                self.assertRaises(ValueError, instance.tick)
                instance.test_started = True
                instance.runner_pid = 123
                instance.tick()  # No new cutoff once original method has started.
            short = monitor.Monitor('cards', 'cards-largest', Mock(pid=42), {'lane': 'cards'}, 250, started=100)
            self.assertEqual(short.startup_until, 250)

    def test_discovery_first_and_last_attempt_do_not_abort_before_300_seconds(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(d, 'DIAGNOSTIC', Path(temporary)), patch.dict(os.environ, ENV):
            metadata = {'lane': 'cards', 'bundles': {'runner': {'bundle_id': 'runner', 'executable': 'Runner'}}}
            instance = monitor.Monitor('cards', 'cards-largest', Mock(pid=42), metadata, 1000, started=100)
            with patch.object(monitor, 'container', return_value=Path('/owned')) as container, \
                 patch.object(monitor, 'discover_runner', return_value=None) as discover:
                with patch.object(monitor.time, 'time', return_value=100):
                    instance.discover()
                self.assertEqual(instance.discovery_attempts, 1)
                self.assertEqual(instance.next_discovery, 105)
                with patch.object(monitor.time, 'time', return_value=104.999):
                    instance.discover()
                self.assertEqual(instance.discovery_attempts, 1)
                for now in range(105, 400, 5):
                    with patch.object(monitor.time, 'time', return_value=now):
                        instance.discover()
                self.assertEqual(instance.discovery_attempts, 60)
                self.assertEqual(instance.next_discovery, 400)
                self.assertEqual(container.call_count, 2)
                self.assertEqual(discover.call_count, 60)
                with patch.object(monitor.time, 'time', return_value=399.999):
                    instance.discover()  # No premature count-limit abort.
                with patch.object(monitor.time, 'time', return_value=400):
                    self.assertRaises(ValueError, instance.tick)

    def test_sample_budget_is_lane_wide_and_prevents_more_processes(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(d, 'DIAGNOSTIC', Path(temporary)), patch.dict(os.environ, ENV):
            process = Mock(pid=42)
            process.poll.return_value = None
            metadata = {'lane': 'cards'}
            first = monitor.Monitor('cards', 'cards-largest', process, metadata, 99999999999)
            d.write(Path(temporary) / 'sample-budget.json', d.identity() | {'allocated': 4, 'maximum': 4})
            with patch.object(monitor, 'process_row', return_value={'executable': '/usr/bin/xcodebuild'}), \
                 patch.object(monitor.subprocess, 'Popen') as spawn:
                first.sample('startup')
                second = monitor.Monitor('cards', 'cards-adaptive', process, metadata, 99999999999)
                second.sample('startup')
                spawn.assert_not_called()
                self.assertIn('cap exhausted', second.report['errors'][-1])

    def test_startup_without_runner_keeps_partial_sample_warning_not_fatal_error(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(d, 'DIAGNOSTIC', Path(temporary)), patch.dict(os.environ, ENV):
            process = Mock(pid=42)
            process.poll.return_value = None
            sampler = Mock(pid=43)
            sampler.wait.return_value = 0
            sampler.poll.return_value = 0
            instance = monitor.Monitor('cards', 'cards-largest', process, {'lane': 'cards'}, 99999999999)
            with patch.object(monitor, 'process_row', return_value={'executable': '/usr/bin/xcodebuild'}), \
                 patch.object(monitor.subprocess, 'Popen', return_value=sampler) as spawn:
                instance.sample('startup-no-test-start-45s')
                self.assertEqual(spawn.call_count, 1)
            self.assertFalse(instance.report['errors'])
            self.assertEqual(len(instance.report['warnings']), 1)
            self.assertEqual(instance.report['samples'][0]['scope'], 'xcodebuild_only')
            self.assertFalse(instance.report['samples'][0]['proves_contemporaneous_stall'])
            instance.runner_pid = 123
            instance.test_started = True
            instance.finish(0)
            self.assertEqual(instance.report['status'], 'complete')

    def test_startup_helpers_use_startup_deadline_not_full_execution_budget(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(d, 'DIAGNOSTIC', Path(temporary)), patch.dict(os.environ, ENV):
            instance = monitor.Monitor('cards', 'cards-largest', Mock(pid=42), {'lane': 'cards'}, 1000, started=100)
            with patch.object(monitor, 'process_row', return_value={'executable': '/usr/bin/xcodebuild'}) as row, \
                 patch.object(monitor, 'targeted_bytes', return_value={}) as sizes:
                instance.snapshot('startup-no-test-start-45s')
                self.assertEqual(row.call_args.args[1], 400)
                self.assertEqual(sizes.call_args.args[1], 400)
                instance.snapshot('termination-marker-arrival')
                self.assertEqual(row.call_args.args[1], 1000)
                self.assertEqual(sizes.call_args.args[1], 1000)

    def trace_fixture(self, directory):
        path = directory / f'reminder-{UUID}.json'
        log = directory / 'reminder.log'
        trace = {'schema_version': 1, 'observation_scope': 'initial_enable', 'session_id': UUID,
                 'export_complete': True, 'dropped_events': 0, 'export_failures': 0,
                 'capture_started_monotonic_ns': 100, 'capture_complete_through_monotonic_ns': 300,
                 'last_sequence': 1, 'events': [{'sequence': 1, 'monotonic_ns': 120,
                     'wall_time_unix': 10.0, 'event': 'session.start', 'fields': {}}]}
        rows = [{'event': 'launch.configured', 'session_id': UUID, 'observation_scope': 'initial_enable'},
                {'event': 'native_tap.return', 'session_id': UUID, 'action_index': 1,
                 'tap_started_monotonic_ns': 150, 'tap_returned_monotonic_ns': 170},
                {'event': 'wait.return', 'session_id': UUID, 'action_index': 1, 'expected': '1',
                 'wait_started_monotonic_ns': 180, 'wait_returned_monotonic_ns': 250, 'completed': False}]
        log.write_text(''.join('DW_REMINDER_UI_DIAGNOSTIC ' + json.dumps(row) + '\n' for row in rows))
        path.write_text(json.dumps(trace))
        return path, log, trace

    def test_failed_wait_can_have_complete_initial_enable_trace(self):
        with tempfile.TemporaryDirectory() as temporary:
            path, log, _ = self.trace_fixture(Path(temporary))
            result = evidence.validate_trace(path, log)
            self.assertFalse(result['initial_enable_wait']['completed'])
            self.assertIn('not whole method', result['coverage'])

    def test_trace_requires_session_contiguity_and_whole_initial_window(self):
        mutations = [lambda x: x.update(events=[]), lambda x: x.update(last_sequence=2),
                     lambda x: x.update(capture_complete_through_monotonic_ns=240),
                     lambda x: x.update(session_id='22222222-2222-4222-8222-222222222222'),
                     lambda x: x.update(dropped_events=1), lambda x: x.update(export_failures=1),
                     lambda x: x['events'][0].update(monotonic_ns=400),
                     lambda x: x['events'][0].pop('event'),
                     lambda x: x['events'][0].pop('wall_time_unix'),
                     lambda x: x['events'][0].update(event='binding.setter', fields={})]
        for mutate in mutations:
            with tempfile.TemporaryDirectory() as temporary:
                path, log, trace = self.trace_fixture(Path(temporary))
                mutate(trace)
                path.write_text(json.dumps(trace))
                self.assertRaises(ValueError, evidence.validate_trace, path, log)

    def test_export_failure_always_writes_structured_inconclusive_result(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(d, 'DIAGNOSTIC', Path(temporary)), patch.dict(os.environ, ENV):
            self.assertEqual(monitor.export_all(), 1)
            result = json.loads((Path(temporary) / 'export.json').read_text())
            self.assertEqual(result['status'], 'inconclusive')
            self.assertTrue(result['errors'])

    def test_missing_bundles_still_keep_independent_structured_evidence(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(d, 'BUILD', Path(temporary)), \
             patch.object(d, 'DIAGNOSTIC', Path(temporary) / 'diagnostic'), patch.dict(os.environ, ENV), \
             patch.object(d, 'run_output', side_effect=ValueError('No Info.plist; Staging retained')):
            (Path(temporary) / 'Diagnostic-cards-largest.xcresult/Staging').mkdir(parents=True)
            result = evidence.collect()
            self.assertFalse(result['diagnostic_evidence_complete'])
            self.assertFalse(result['acceptance'])
            self.assertTrue(result['tests']['cards-largest']['bundle_exists'])
            self.assertFalse(result['tests']['cards-largest']['info_plist_exists'])
            self.assertTrue((Path(temporary) / 'Diagnostic-cards-largest.xcresult/Staging').exists())
            self.assertIn('validate.markers.cards-largest', result['errors'])


if __name__ == '__main__':
    unittest.main()

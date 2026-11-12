"""Pure fixtures/mocks only. Never boots, builds, runs, or samples an app."""
import copy
import json
import os
import plistlib
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import diagnostic as d
import diagnostic_monitor as monitor
import diagnostic_postrun as postrun
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
    return dict(counts, startTime=150, finishTime=180, totalTestCount=1, result='Passed', devicesAndConfigurations=[dict(counts, device={
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
        self.assertEqual([selector for pairs in d.LANES.values() for _, selector in pairs], [
            'DailyWhiskersTests/DailyCardShareVisualTests/testAdaptiveViewportRetainsArtworkScaleAndNaturalScrollingHeight',
            'DailyWhiskersUITests/RegressionSmokeTests/testAccountToolsOpenAndDismiss',
            'DailyWhiskersUITests/ReminderUITests/testPermissionRevocationRegrantAndExplicitDisable',
            'DailyWhiskersUITests/SavedCardsTests/testLargestTextLandscapeSavedCardActionsAndVibe',
            'DailyWhiskersUITests/SavedCardsTests/testAdaptiveCardAndSavedTilesAcrossWindowSizes'])

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

    def test_workflow_manages_launch_under_one_original_budget(self):
        text = (ROOT / '.github/workflows/ios.yml').read_text()
        steps = re.split(r'^      - ', text, flags=re.M)[1:]
        commands = []
        for step in steps[:9]:
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
            selected, selected])
        self.assertIn('ref: ${{ github.sha }}', steps[0])
        self.assertIn('test "$GITHUB_SHA" = "$EXPECTED_SOURCE_SHA"', steps[1])
        self.assertIn('test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"', steps[1])
        self.assertIn('echo "TESTED_SHA=$(git rev-parse HEAD)" >> "$GITHUB_ENV"', steps[1])
        self.assertEqual(text.count('init-budget'), 1)
        self.assertNotIn('diagnostic.py boot', text)
        self.assertNotIn('simctl boot', text)
        self.assertNotIn('bootstatus', text)
        self.assertFalse(hasattr(d, 'boot'))
        self.assertIn("github.ref == 'refs/heads/codex/ci-managed-launch-20261111'", text)
        self.assertNotIn('CI_EXECUTION_DEADLINE', text)  # No per-stage deadline reset.

    def test_identity_rejects_missing_or_cross_source_lane(self):
        with patch.dict(os.environ, ENV, clear=True):
            self.assertEqual(d.identity()['lane'], 'cards')
            for key, value in [('GITHUB_JOB', 'ui-shards'), ('TESTED_SHA', 'b' * 40), ('CI_SHARD_ID', 'settings'), ('GITHUB_RUN_ID', ''), ('GITHUB_RUN_ATTEMPT', '2')]:
                with self.subTest(key=key), patch.dict(os.environ, {key: value}):
                    self.assertRaises(ValueError, d.identity)

    def test_preparation_rejects_preexisting_or_mismatched_ownership(self):
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
                     lambda s, t: s['devicesAndConfigurations'][0].update(passedTests=2),
                     lambda s, t: s['devicesAndConfigurations'][0].update(passedTests=0, failedTests=1),
                     lambda s, t: s['devicesAndConfigurations'][0].update(passedTests=0, skippedTests=1),
                     lambda s, t: s['devicesAndConfigurations'][0].update(passedTests=0, expectedFailures=1)]
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
        with patch.object(monitor, 'host_output', return_value='10 /other/Runner\n11 /owned/Runner'):
            self.assertEqual(monitor.discover_runner(Path('/owned/Runner'), 123), 11)
        with patch.object(monitor, 'host_output', return_value='11 /owned/Runner\n12 /owned/Runner'):
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
            self.assertIn('validate.postrun.cards-largest', result['errors'])


class ManagedLaunchTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.build = self.root / 'build'
        self.directory = self.build / 'diagnostic'
        for target, value in [('BUILD', self.build), ('DIAGNOSTIC', self.directory)]:
            patcher = patch.object(d, target, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        env = patch.dict(os.environ, ENV | {'SIMULATOR_ID': UUID, 'CI_EXECUTION_DEADLINE': '2800',
                         'GITHUB_WORKSPACE': str(self.root)}, clear=True)
        env.start()
        self.addCleanup(env.stop)
        timer = patch.object(d.time, 'time', return_value=200)
        timer.start()
        self.addCleanup(timer.stop)
        self.current = d.identity()
        verifier = patch.object(postrun, 'verify_evidence', return_value={'fixture': 'independently tested in test_diagnostic_postrun'})
        verifier.start()
        self.addCleanup(verifier.stop)
        self.prep = simulator.identity() | {'status': 'ready', 'readback_verified': True, 'ownership': 'created',
            'simulator_id': UUID, 'preexisting_ids': [], 'runtime': simulator.RUNTIME, 'version': simulator.VERSION,
            'build': simulator.BUILD, 'architecture': 'arm64', 'name': simulator.NAME, 'device_type': simulator.DEVICE_TYPE}
        d.write(self.build / 'simulator.json', self.prep)
        d.write(self.build / 'job-budget.json', self.current | {'execution_seconds': 2700, 'started': 100, 'deadline': 2800})

    def launch(self, stage='cards-largest'):
        value = dict(self.current, stage=stage, pid=42, deadline=2800, command=d.test_command('cards', stage),
                     started=140, started_monotonic_ns=100, monotonic_clock_domain=postrun.MARKER_CLOCK_DOMAIN, evidence_mode='post-run-only')
        d.write(self.directory / stage / 'exit.json', dict(self.current, stage=stage, launch=value,
                exit_code=0, finished=190, finished_monotonic_ns=1000, monotonic_clock_domain=postrun.MARKER_CLOCK_DOMAIN))
        d.write(self.directory / stage / 'launch.json', value)
        bundle = self.build / f'Diagnostic-{stage}.xcresult'
        bundle.mkdir(exist_ok=True)
        (bundle / 'Info.plist').write_text('fixture only')
        return value

    def good_checkpoint(self):
        self.launch()
        with patch.object(d, 'run_output', side_effect=[json.dumps(summary()), json.dumps(tree())]) as reader:
            record = evidence.checkpoint('cards-largest', 0)
            self.assertEqual(reader.call_count, 2)
            self.assertTrue(all(call.kwargs == {'seconds': 20, 'until': 2800} for call in reader.call_args_list))
        status = simulator.identity() | {'stage': 'cards-largest', 'status': 'success', 'exit_code': 0, 'deadline': 2800}
        d.write(self.build / 'cards-largest-status.json', status)
        return record

    def test_checkpoint_and_dependent_method_require_actual_result_not_boot(self):
        record = self.good_checkpoint()
        self.assertEqual(record['status'], 'success')
        self.assertFalse((self.directory / 'boot.json').exists())
        evidence.verify_predecessor('cards', 'cards-adaptive')
        self.assertEqual(evidence.validate_checkpoint(record, 'cards-largest', self.current, 2800, UUID), SELECTOR)

    def test_complete_visual_collection_needs_no_boot_and_rejects_missing_provenance(self):
        with patch.dict(os.environ, {'CI_DIAGNOSTIC_LANE': 'visual', 'CI_SHARD_ID': 'visual'}):
            current = d.identity()
            d.write(self.build / 'simulator.json', self.prep | {'shard': 'visual'})
            d.write(self.build / 'job-budget.json', current | {'execution_seconds': 2700, 'started': 100, 'deadline': 2800})
            for name in ('prepare', 'diagnostic-preflight', 'resolve', 'diagnostic-build', 'visual', 'cleanup'):
                record = simulator.identity() | {'stage': name, 'status': 'success', 'exit_code': 0, 'deadline': 2800}
                if name == 'cleanup':
                    record.update(operation='delete-owned', simulator_id=UUID, readback_verified=True)
                d.write(self.build / f'{name}-status.json', record)
            (self.build / 'toolchain.txt').write_text('\n'.join([
                'Developer directory: ' + simulator.DEVELOPER_DIR, 'Architecture: arm64',
                'Xcode 27.2', 'Build version 27B52', 'Simulator SDK: 27.2', 'Apple Swift version fixture']))
            d.write(self.directory / 'preflight.json', current | {'status': 'success', 'cache_restore': 'disabled', 'cache_save': 'disabled',
                'evidence_mode': 'post-run-only', 'monotonic_clock_domain': postrun.MARKER_CLOCK_DOMAIN})
            d.write(self.directory / 'export.json', current | {'status': 'complete', 'errors': []})
            d.write(self.directory / 'built-metadata.json', current)
            launch = current | {'stage': 'visual', 'pid': 42, 'deadline': 2800, 'command': d.test_command('visual', 'visual'),
                                'started': 140, 'started_monotonic_ns': 100, 'monotonic_clock_domain': postrun.MARKER_CLOCK_DOMAIN, 'evidence_mode': 'post-run-only'}
            d.write(self.directory / 'visual/exit.json', current | {'stage': 'visual', 'launch': launch,
                    'exit_code': 0, 'finished': 190, 'finished_monotonic_ns': 1000, 'monotonic_clock_domain': postrun.MARKER_CLOCK_DOMAIN})
            d.write(self.directory / 'visual/launch.json', launch)
            bundle = self.build / 'Diagnostic-visual.xcresult'
            bundle.mkdir()
            (bundle / 'Info.plist').write_text('fixture')
            selected = d.LANES['visual'][0][1]
            visual_tree = {'testNodes': [{'nodeType': 'Test Case', 'result': 'Passed',
                'nodeIdentifier': '/'.join(selected.split('/')[1:]) + '()', 'nodeIdentifierURL': 'test://' + selected}]}
            with patch.object(d, 'run_output', side_effect=[json.dumps(summary()), json.dumps(visual_tree)]):
                checkpoint = evidence.checkpoint('visual', 0)
            def collect():
                with patch.object(d, 'run_output', side_effect=[json.dumps(summary()), json.dumps(visual_tree)]):
                    return evidence.collect()
            result = collect()
            self.assertTrue(result['diagnostic_evidence_complete'], result['errors'])
            self.assertTrue(result['selected_tests_passed'])
            self.assertFalse(result['acceptance'])
            self.assertNotIn('boot', result)
            self.assertFalse((self.directory / 'boot.json').exists())
            for mutation in [{'status': 'failure'}, {'run_attempt': '2'}, {'simulator_id': 'foreign'}]:
                d.write(self.directory / 'visual/verified-result.json', checkpoint | mutation)
                result = collect()
                self.assertFalse(result['diagnostic_evidence_complete'])
                self.assertTrue(result['selected_tests_passed'])  # Result pass independent of checkpoint provenance.
            d.write(self.directory / 'visual/verified-result.json', checkpoint)
            (self.directory / 'visual/launch.json').unlink()
            result = collect()
            self.assertFalse(result['diagnostic_evidence_complete'])
            self.assertFalse(result['selected_tests_passed'])

    def test_budget_source_attempt_and_absolute_deadline_are_not_replaceable(self):
        original = d.budget()
        for key, value in [('execution_seconds', 3000), ('deadline', 2801), ('started', 101),
                           ('source_sha', 'b' * 40), ('run_id', '13'), ('run_attempt', '2'),
                           ('job', 'other'), ('shard', 'other')]:
            with self.subTest(key=key):
                d.write(self.build / 'job-budget.json', original | {key: value})
                self.assertRaises(ValueError, d.deadline)
        d.write(self.build / 'job-budget.json', original)
        with patch.object(d.time, 'time', return_value=2800):
            self.assertRaises(ValueError, d.deadline)

    def test_checkpoint_rejects_failed_foreign_missing_and_unlaunched_results(self):
        self.launch()
        for key, value in [('deviceId', 'foreign'), ('modelName', 'other'), ('deviceName', 'other'),
                           ('architecture', 'x86_64'), ('osVersion', '27.1'), ('osBuildNumber', 'other'),
                           ('platform', 'iOS')]:
            broken = summary()
            broken['devicesAndConfigurations'][0]['device'][key] = value
            with self.subTest(key=key), patch.object(d, 'run_output', side_effect=[json.dumps(broken), json.dumps(tree())]):
                self.assertRaises(ValueError, evidence.checkpoint, 'cards-largest', 0)
        for code in (1, 65, 124):
            with patch.object(d, 'run_output', side_effect=[json.dumps(summary()), json.dumps(tree())]):
                self.assertRaises(ValueError, evidence.checkpoint, 'cards-largest', code)
        for broken in [None, {}, dict(summary(), failedTests=1, passedTests=0),
                       dict(summary(), skippedTests=1, passedTests=0)]:
            with patch.object(d, 'run_output', side_effect=[json.dumps(broken), json.dumps(tree())]):
                self.assertRaises(ValueError, evidence.checkpoint, 'cards-largest', 0)
        with patch.object(d, 'run_output', side_effect=[json.dumps(summary()), ValueError('No test tree')]):
            self.assertRaises(ValueError, evidence.checkpoint, 'cards-largest', 0)
        saved = json.loads((self.directory / 'cards-largest/verified-result.json').read_text())
        self.assertEqual(saved['summary'], summary())  # Independent evidence survives.
        self.assertEqual(saved['status'], 'failure')
        (self.directory / 'cards-largest/launch.json').unlink()
        with patch.object(d, 'run_output') as reader:
            self.assertRaises(ValueError, evidence.checkpoint, 'cards-largest', 0)
            reader.assert_not_called()

    def test_unfinalized_result_preserves_staging_and_never_unlocks_next_method(self):
        self.launch()
        bundle = self.build / 'Diagnostic-cards-largest.xcresult'
        (bundle / 'Info.plist').unlink()
        (bundle / 'Staging').mkdir()
        with patch.object(d, 'run_output') as reader:
            self.assertRaises(ValueError, evidence.checkpoint, 'cards-largest', 0)
            reader.assert_not_called()
        self.assertTrue((bundle / 'Staging').is_dir())
        with patch.object(postrun, 'execute') as execute:
            self.assertRaises(FileNotFoundError, d.test, 'cards', 'cards-adaptive')
            execute.assert_not_called()

    def test_checkpoint_and_launch_mutations_block_second_method(self):
        record = self.good_checkpoint()
        for key, value in [('source_sha', 'b' * 40), ('tested_sha', 'b' * 40), ('event_sha', 'b' * 40),
                           ('run_id', '13'), ('run_attempt', '2'), ('shard', 'other'), ('lane', 'other'),
                           ('deadline', 2900), ('status', 'failure'), ('exit_code', 65), ('simulator_id', 'foreign'),
                           ('errors', {'summary': 'unavailable'})]:
            with self.subTest(key=key):
                d.write(self.directory / 'cards-largest/verified-result.json', record | {key: value})
                with patch.object(postrun, 'execute') as execute:
                    self.assertRaises(ValueError, d.test, 'cards', 'cards-adaptive')
                    execute.assert_not_called()
        for change in [lambda x: x['launch'].update(run_attempt='2'),
                       lambda x: x['launch'].update(pid=None),
                       lambda x: x['launch'].update(pid=43),
                       lambda x: x['launch'].update(command=['xcodebuild', 'test']),
                       lambda x: x['launch']['command'].__setitem__(x['launch']['command'].index('-destination') + 1,
                                                                 'platform=iOS Simulator,id=foreign,arch=arm64'),
                       lambda x: x['summary']['devicesAndConfigurations'][0]['device'].update(deviceId='foreign'),
                       lambda x: x['tree']['testNodes'][0].update(result='Failed')]:
            broken = copy.deepcopy(record)
            change(broken)
            d.write(self.directory / 'cards-largest/verified-result.json', broken)
            self.assertRaises(ValueError, evidence.verify_predecessor, 'cards', 'cards-adaptive')
        d.write(self.directory / 'cards-largest/verified-result.json', record)
        status = json.loads((self.build / 'cards-largest-status.json').read_text())
        for change in [{'status': 'failure'}, {'exit_code': 65}, {'source_sha': 'b' * 40}, {'run_attempt': '2'},
                       {'deadline': 2801}, {'cleanup_errors': ['denied']}]:
            d.write(self.build / 'cards-largest-status.json', status | change)
            self.assertRaises(ValueError, evidence.verify_predecessor, 'cards', 'cards-adaptive')

    def test_test_path_validates_before_return_and_forbids_repeated_launch(self):
        with patch.object(d, 'check_lock'), patch.object(postrun, 'execute', return_value=0) as execute, \
             patch.object(evidence, 'checkpoint', side_effect=ValueError('foreign result')) as check:
            self.assertRaises(ValueError, d.test, 'cards', 'cards-largest')
            check.assert_called_once_with('cards-largest', 0)
            command = execute.call_args.args[0]
            self.assertEqual(command[0:2], ['xcodebuild', 'test-without-building'])
            self.assertEqual(command[command.index('-destination') + 1], f'platform=iOS Simulator,id={UUID},arch=arm64')
            self.assertEqual([arg for arg in command if arg.startswith('-only-testing:')], ['-only-testing:' + SELECTOR])
        self.launch()
        with patch.object(postrun, 'execute') as execute:
            self.assertRaises(ValueError, d.test, 'cards', 'cards-largest')
            execute.assert_not_called()

    def test_discovery_tolerates_only_bounded_known_startup_states(self):
        metadata = dict(self.current, bundles={'runner': {'bundle_id': 'runner', 'executable': 'Runner'}})
        command = ['xcrun', 'simctl', 'get_app_container', UUID, 'runner', 'app']
        header = 'An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):\n'
        for state in ('Shutdown', 'Booting'):
            instance = monitor.Monitor('cards', 'cards-largest', Mock(pid=42), metadata, 2800, started=200)
            with patch.object(monitor, 'container', side_effect=subprocess.CalledProcessError(
                    149, command, output=header + 'Unable to lookup in current state: ' + state)):
                instance.discover()
                self.assertIsNone(instance.runner_pid)
                self.assertFalse(instance.test_started)
                self.assertEqual(instance.report['container_unavailable'][0]['transitional_state'], True)
                self.assertEqual(instance.startup_until, 500)
        missing = 'An error was encountered processing the command (domain=NSPOSIXErrorDomain, code=2):\nNo such file or directory'
        instance = monitor.Monitor('cards', 'cards-largest', Mock(pid=42), metadata, 2800, started=200)
        with patch.object(monitor, 'container', side_effect=subprocess.CalledProcessError(2, command, output=missing)):
            instance.discover()
            self.assertFalse(instance.report['container_unavailable'][0]['transitional_state'])
        shutdown = header + 'Unable to lookup in current state: Shutdown'
        for error in [subprocess.CalledProcessError(1, command, output='Access denied'),
                      subprocess.CalledProcessError(149, command, output=header + 'Unable to lookup in current state: Unknown'),
                      subprocess.CalledProcessError(149, command, output=shutdown + '\nAccess denied'),
                      subprocess.CalledProcessError(149, command, output='Fatal error\n' + shutdown),
                      subprocess.CalledProcessError(127, command, output=shutdown),
                      subprocess.CalledProcessError(127, command, output='xcrun tool not found'),
                      subprocess.CalledProcessError(2, command, output=missing + '\npermission denied'),
                      subprocess.CalledProcessError(2, command, output='not installed'),
                      subprocess.CalledProcessError(149, command[:3] + ['foreign'] + command[4:], output=shutdown),
                      subprocess.CalledProcessError(149, command[:4] + ['foreign', 'app'], output=shutdown),
                      subprocess.CalledProcessError(149, ['/bin/ps'], output=shutdown),
                      subprocess.TimeoutExpired(command, 3)]:
            instance = monitor.Monitor('cards', 'cards-largest', Mock(pid=42), metadata, 2800, started=200)
            with patch.object(monitor, 'container', side_effect=error):
                self.assertRaises((ValueError, subprocess.TimeoutExpired), instance.discover)
        instance = monitor.Monitor('cards', 'cards-largest', Mock(pid=42), metadata, 2800, started=200)
        with patch.object(monitor, 'container', return_value=Path('/owned')), \
             patch.object(monitor, 'discover_runner', side_effect=subprocess.CalledProcessError(
                 2, ['/bin/ps'], output='No such file or directory')):
            self.assertRaises(subprocess.CalledProcessError, instance.discover)

    def container_fixture(self):
        home = self.root / 'home'
        root = home / 'Library/Developer/CoreSimulator/Devices' / UUID
        data = root / 'data'
        container = data / 'Containers/Data/Application' / UUID
        container.mkdir(parents=True)
        info = {'UDID': UUID, 'name': simulator.NAME, 'runtime': simulator.RUNTIME,
                'deviceType': simulator.DEVICE_TYPE, 'isDeleted': False}
        (root / 'device.plist').write_bytes(plistlib.dumps(info))
        meta = container / '.com.apple.mobile_container_manager.metadata.plist'
        meta.write_bytes(plistlib.dumps({'MCMMetadataIdentifier': 'runner.bundle'}))
        d.write(self.build / 'simulator-devices-prepared.json', {'devices': {simulator.RUNTIME: [{
            'udid': UUID, 'name': simulator.NAME, 'deviceTypeIdentifier': simulator.DEVICE_TYPE,
            'isAvailable': True, 'dataPath': str(data), 'state': 'Shutdown'}]}})
        return home, root, container, meta, info

    def test_shutdown_export_uses_exact_owned_metadata_without_simctl(self):
        home, root, container, meta, info = self.container_fixture()
        with patch.object(Path, 'home', return_value=home), patch.object(d, 'run_output') as command:
            self.assertEqual(monitor.exported_container({'bundle_id': 'runner.bundle'}, 2800), (container, meta))
            command.assert_not_called()
            for key, value in [('UDID', 'foreign'), ('runtime', 'foreign'), ('deviceType', 'foreign'),
                               ('name', 'foreign'), ('isDeleted', True)]:
                (root / 'device.plist').write_bytes(plistlib.dumps(info | {key: value}))
                self.assertRaises(ValueError, monitor.exported_container, {'bundle_id': 'runner.bundle'}, 2800)
            (root / 'device.plist').write_bytes(plistlib.dumps(info))
            self.assertRaises(ValueError, monitor.exported_container, {'bundle_id': 'foreign'}, 2800)
            self.assertRaises(ValueError, monitor.exported_container, {'bundle_id': 'runner.bundle'}, 199)
            extra = container.parent / '22222222-2222-4222-8222-222222222222'
            extra.mkdir()
            (extra / meta.name).write_bytes(meta.read_bytes())
            self.assertRaises(ValueError, monitor.exported_container, {'bundle_id': 'runner.bundle'}, 2800)

    def test_unlaunched_export_is_explicitly_inconclusive_without_container_access(self):
        d.write(self.directory / 'built-metadata.json', dict(self.current, bundles={'runner': {'bundle_id': 'runner.bundle'}}))
        with patch.object(monitor, 'exported_container') as container, patch.object(d, 'run_output') as command:
            self.assertEqual(monitor.export_all(), 1)
            container.assert_not_called()
            command.assert_not_called()
        record = json.loads((self.directory / 'export.json').read_text())
        self.assertEqual(record['status'], 'inconclusive')
        self.assertEqual(record['launched_stages'], [])
        self.assertIn('No selected method launched', record['errors'][0])


if __name__ == '__main__':
    unittest.main()

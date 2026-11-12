"""Pure post-run fixtures; no Xcode, simulator launch or live observation."""
import copy
import json
import os
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest.mock import Mock, patch

import diagnostic as d
import diagnostic_postrun as p
import diagnostic_results as r
from test_diagnostic import ENV, UUID, SELECTOR, marker_rows, summary, tree


class PostrunTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.build = self.root / 'build'
        self.diag = self.build / 'diagnostic'
        self.directory = self.diag / 'cards-largest'
        self.directory.mkdir(parents=True)
        for target, value in [('BUILD', self.build), ('DIAGNOSTIC', self.diag)]:
            patcher = patch.object(d, target, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        for patcher in [patch.dict(os.environ, ENV | {'GITHUB_WORKSPACE': str(self.root)}, clear=True),
                        patch.object(d, 'owned', return_value={'simulator_id': UUID}),
                        patch.object(d, 'deadline', return_value=2800),
                        patch.object(d, 'budget', return_value={'deadline': 2800})]:
            patcher.start()
            self.addCleanup(patcher.stop)
        self.current = d.identity()
        self.launch = dict(self.current, stage='cards-largest', pid=42, deadline=2800,
                           command=d.test_command('cards', 'cards-largest'), started=9,
                           started_monotonic_ns=90, monotonic_clock_domain=p.MARKER_CLOCK_DOMAIN, evidence_mode='post-run-only')
        self.exited = dict(self.current, stage='cards-largest', launch=self.launch,
                           exit_code=0, finished=11, finished_monotonic_ns=110, monotonic_clock_domain=p.MARKER_CLOCK_DOMAIN)
        self.metadata = dict(self.current, bundles={kind: {'bundle_id': kind + '.bundle',
            'executable': 'Runner' if kind == 'runner' else 'App', 'binaries': {'binary': 'hash'},
            'built_path': str(self.root / kind)} for kind in ('app', 'runner')})
        d.write(self.diag / 'built-metadata.json', self.metadata)
        d.write(self.directory / 'launch.json', self.launch)
        d.write(self.directory / 'exit.json', self.exited)

    def stream(self, rows=None):
        path = self.directory / 'exported/runner' / f'cards-123-{UUID}.jsonl'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(''.join(json.dumps(row) + '\n' for row in (marker_rows() if rows is None else rows)))
        return path

    def validate(self, path):
        return p.validate_stream(path, 'cards-largest', self.launch, self.exited, '/owned', self.metadata)

    def fixture(self):
        file = self.stream()
        export = dict(self.current, status='complete', errors=[], launched_stages=['cards-largest'],
                      containers=[], files=[{'kind': 'runner', 'path': str(file), 'source': '/owned/Documents/ci-diagnostic/' + file.name,
                                            'sha256': p.digest(file)}])
        for kind in ('app', 'runner'):
            receipt = self.directory / f'{kind}-container-metadata.plist'
            receipt.write_bytes(plistlib.dumps({'MCMMetadataIdentifier': kind + '.bundle'}))
            export['containers'].append({'kind': kind, 'bundle_id': kind + '.bundle',
                                         'path': '/owned' if kind == 'runner' else '/owned-app', 'metadata': str(receipt)})
        d.write(self.diag / 'cards-largest-export.json', export)
        report = dict(self.current, stage='cards-largest', mode='post-run-only', installed={
            kind: {'bundle_id': kind + '.bundle', 'binaries': {'binary': 'hash'}} for kind in ('app', 'runner')})
        d.write(self.directory / 'postrun.json', report)
        return export, report

    def test_complete_stream_uses_postrun_identity_without_live_claim(self):
        result = self.validate(self.stream())
        self.assertEqual(result['pid'], 123)
        self.assertFalse(result['live_runner_observed'])
        self.assertIn('POST-RUN', result['identity_basis'])

    def test_marker_timestamp_and_identity_mutations_fail_closed(self):
        mutations = [('event_wall_time', float('nan')), ('event_wall_time', True),
                     ('event_wall_time', 8), ('export_wall_time', 12), ('export_wall_time', 9.5),
                     ('event_monotonic_ns', '89'), ('export_monotonic_ns', '111'),
                     ('event_monotonic_ns', '-1'), ('event_monotonic_ns', 'nan'),
                     ('event_monotonic_ns', 100), ('process_name', 'Other'), ('pid', True),
                     ('runner_bundle_id', 'foreign'), ('container_home', '/foreign'),
                     ('session_id', 'wrong'), ('test', '-[Other testForeign]'), ('stream', 'startup')]
        for key, value in mutations:
            with self.subTest(key=key, value=value):
                rows = marker_rows()
                rows[0][key] = value
                self.assertRaises((ValueError, KeyError, TypeError), self.validate, self.stream(rows))

    def test_empty_partial_wrong_filename_and_ambiguous_streams_rejected(self):
        for content in ('', '{', json.dumps(marker_rows()[0])):
            path = self.stream()
            path.write_text(content)
            self.assertRaises((ValueError, KeyError), self.validate, path)
        path = self.stream()
        wrong = path.with_name('cards-999-' + UUID + '.jsonl')
        path.rename(wrong)
        self.assertRaises(ValueError, self.validate, wrong)

    def test_frozen_stage_export_verifies(self):
        self.fixture()
        result = p.verify_evidence('cards-largest', collect=True)
        self.assertEqual(result['status'], 'complete')
        self.assertEqual(result['marker_evidence']['events'], 4)

    def test_unrecorded_missing_corrupt_and_unattributed_files_rejected(self):
        for mode in ('unrecorded', 'missing', 'corrupt', 'foreign', 'empty', 'partial', 'duplicate'):
            with self.subTest(mode=mode):
                export, _ = self.fixture()
                folder = self.directory / 'exported/runner'
                for file in folder.iterdir():
                    if file.name != f'cards-123-{UUID}.jsonl':
                        file.unlink()
                file = next(folder.glob('*.jsonl'))
                if mode == 'unrecorded':
                    (folder / 'unexpected.jsonl').write_text('{}\n')
                elif mode == 'missing':
                    file.unlink()
                elif mode == 'corrupt':
                    file.write_text('{}\n')
                else:
                    rows = marker_rows()
                    if mode == 'foreign':
                        rows[0]['test'] = '-[Other testForeign]'
                    content = '' if mode == 'empty' else ''.join(json.dumps(row) + '\n' for row in rows)
                    file.write_text(content.rstrip('\n') if mode == 'partial' else content)
                    export['files'][0]['sha256'] = p.digest(file)
                    if mode == 'duplicate':
                        extra = folder / 'duplicate.jsonl'
                        extra.write_text(content)
                        export['files'].append(dict(export['files'][0], path=str(extra), source='/owned/' + extra.name))
                    d.write(self.diag / 'cards-largest-export.json', export)
                self.assertRaises((ValueError, FileNotFoundError), p.verify_evidence, 'cards-largest', collect=True)

    def test_invocation_identity_and_time_mutations_fail_closed(self):
        p.validate_invocation(self.launch, self.exited, 'cards-largest')
        for key, value in [('finished', 8), ('finished', 2801), ('finished', float('inf')),
                           ('finished_monotonic_ns', 89), ('finished_monotonic_ns', True),
                           ('source_sha', 'b' * 40), ('stage', 'cards-adaptive')]:
            self.assertRaises(ValueError, p.validate_invocation, self.launch, self.exited | {key: value}, 'cards-largest')

    def test_finalized_result_bound_to_actual_invocation(self):
        good = summary() | {'startTime': 9.2, 'finishTime': 10.8}
        r.validate_result_invocation(good, self.launch, 'cards-largest')
        for change in [{'startTime': 8}, {'finishTime': 12}, {'startTime': float('nan')},
                       {'finishTime': True}, {'startTime': 10.9, 'finishTime': 10.8}]:
            self.assertRaises(ValueError, r.validate_result_invocation, good | change, self.launch, 'cards-largest')

    def test_execute_waits_only_in_inherited_group_and_keeps_exit_code(self):
        process = Mock(pid=42)
        process.wait.return_value = 65
        command = d.test_command('cards', 'cards-largest')
        with patch.object(p, 'marker_uptime_ns', return_value=100), \
             patch.object(p.subprocess, 'Popen', return_value=process) as launch, \
             patch.object(p, 'export_all') as export, patch.object(p, 'installed_bundles') as installed:
            self.assertEqual(p.execute(command, 'cards', 'cards-largest'), 65)
            launch.assert_called_once_with(command)
            process.wait.assert_called_once_with()
            export.assert_not_called()
            installed.assert_not_called()
        self.assertEqual(json.loads((self.directory / 'exit.json').read_text())['exit_code'], 65)

    def test_preflight_does_not_require_sample_or_process_tools(self):
        with patch.dict(os.environ, {'GITHUB_EVENT_NAME': 'workflow_dispatch',
                'GITHUB_REF': 'refs/heads/codex/ci-managed-launch-20261111'}), \
             patch.object(p, 'marker_uptime_ns', return_value=100), \
             patch.object(d, 'run_output', side_effect=AssertionError('Unexpected subprocess')):
            d.preflight()
        record = json.loads((self.diag / 'preflight.json').read_text())
        self.assertEqual(record['evidence_mode'], 'post-run-only')
        self.assertIsNone(record['startup_cutoff_seconds'])

    def test_product_pass_survives_diagnostic_failure_but_checkpoint_blocks(self):
        bundle = self.build / 'Diagnostic-cards-largest.xcresult'
        bundle.mkdir()
        (bundle / 'Info.plist').write_text('fixture')
        with patch.object(d, 'run_output', side_effect=[json.dumps(summary() | {'startTime': 9.2, 'finishTime': 10.8}), json.dumps(tree())]), \
             patch.object(p, 'verify_evidence', side_effect=ValueError('missing markers')):
            self.assertRaises(ValueError, r.checkpoint, 'cards-largest', 0)
        record = json.loads((self.directory / 'verified-result.json').read_text())
        self.assertTrue(record['product_test_passed'])
        self.assertFalse(record['postrun_evidence_complete'])
        self.assertEqual(record['status'], 'failure')

    def test_installed_payloads_must_match_built_app_debug_and_ui_executables(self):
        home = self.root / 'home'
        root = home / 'Library/Developer/CoreSimulator/Devices' / UUID / 'data/Containers/Bundle/Application'
        metadata = copy.deepcopy(self.metadata)
        for kind in ('app', 'runner'):
            built = self.root / kind
            installed = root / kind / (kind + '.app')
            binaries = ([metadata['bundles'][kind]['executable'], 'App.debug.dylib'] if kind == 'app'
                        else ['Runner', 'PlugIns/DailyWhiskersUITests.xctest/DailyWhiskersUITests'])
            metadata['bundles'][kind]['binaries'] = {}
            for relative in binaries:
                for folder in (built, installed):
                    file = folder / relative
                    file.parent.mkdir(parents=True, exist_ok=True)
                    file.write_bytes(relative.encode())
                metadata['bundles'][kind]['binaries'][relative] = p.digest(built / relative)
            (installed / 'Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': kind + '.bundle', 'CFBundleExecutable': metadata['bundles'][kind]['executable']}))
        with patch.object(Path, 'home', return_value=home), patch.object(p.time, 'time', return_value=200):
            result = p.installed_bundles(metadata, 2800)
            self.assertIn('App.debug.dylib', result['app']['binaries'])
            for kind, relative in [('app', 'App.debug.dylib'), ('runner', 'PlugIns/DailyWhiskersUITests.xctest/DailyWhiskersUITests')]:
                file = root / kind / (kind + '.app') / relative
                original = file.read_bytes()
                file.write_bytes(b'foreign')
                self.assertRaises(ValueError, p.installed_bundles, metadata, 2800)
                file.write_bytes(original)
            self.assertRaises(ValueError, p.installed_bundles, metadata, 199)

    def test_failed_product_still_attempts_independent_postrun_evidence(self):
        bundle = self.build / 'Diagnostic-cards-largest.xcresult'
        bundle.mkdir()
        (bundle / 'Info.plist').write_text('fixture')
        with patch.object(d, 'run_output', side_effect=[json.dumps(summary()), json.dumps(tree())]), \
             patch.object(p, 'verify_evidence', return_value={'status': 'complete'}) as verify:
            self.assertRaises(ValueError, r.checkpoint, 'cards-largest', 65)
            verify.assert_called_once_with('cards-largest')
        record = json.loads((self.directory / 'verified-result.json').read_text())
        self.assertFalse(record['product_test_passed'])
        self.assertTrue(record['postrun_evidence_complete'])
        self.assertEqual(record['status'], 'failure')

    def test_missing_partial_or_failed_xcresult_never_unlocks(self):
        for reader_error in (FileNotFoundError('unfinalized'), ValueError('malformed summary')):
            with patch.object(d, 'run_output', side_effect=reader_error), \
                 patch.object(p, 'verify_evidence', return_value={'status': 'complete'}):
                self.assertRaises(ValueError, r.checkpoint, 'cards-largest', 0)
                record = json.loads((self.directory / 'verified-result.json').read_text())
                self.assertFalse(record['product_test_passed'])
                self.assertEqual(record['status'], 'failure')

    def test_shared_clock_never_uses_python_process_relative_epoch(self):
        absolute = 22_600_000_000_000
        with patch.object(p.sys, 'platform', 'darwin'), \
             patch.object(p.time, 'CLOCK_UPTIME_RAW', 8, create=True), \
             patch.object(p.time, 'clock_gettime_ns', return_value=absolute, create=True) as raw, \
             patch.object(p.time, 'monotonic_ns', side_effect=AssertionError('Process-relative clock forbidden')):
            self.assertEqual(p.marker_uptime_ns(), absolute)
            raw.assert_called_once_with(8)
            for invalid in (0, -1, True, 1.0):
                raw.return_value = invalid
                self.assertRaises(ValueError, p.marker_uptime_ns)

    def test_unavailable_clock_fails_closed_before_build_or_test(self):
        with patch.object(p.sys, 'platform', 'linux'):
            self.assertRaises(ValueError, p.marker_uptime_ns)
        with patch.object(p.time, 'clock_gettime_ns', None):
            self.assertRaises(ValueError, p.marker_uptime_ns)
        with patch.object(p.time, 'clock_gettime_ns', side_effect=OSError('unsupported clock')):
            self.assertRaises(OSError, p.marker_uptime_ns)
        with patch.dict(os.environ, {'GITHUB_EVENT_NAME': 'workflow_dispatch',
                'GITHUB_REF': 'refs/heads/codex/ci-managed-launch-20261111'}), \
             patch.object(p, 'marker_uptime_ns', side_effect=ValueError('unavailable')), \
             patch.object(d, 'run_output') as command:
            self.assertRaises(ValueError, d.preflight)
            command.assert_not_called()
            self.assertFalse((self.diag / 'preflight.json').exists())

    def test_legacy_or_mismatched_clock_receipts_cannot_be_requalified(self):
        for value in (None, 'python.monotonic_ns', 'darwin.CLOCK_MONOTONIC_RAW'):
            self.assertRaises(ValueError, p.validate_invocation,
                              self.launch | {'monotonic_clock_domain': value}, self.exited, 'cards-largest')
            self.assertRaises(ValueError, p.validate_invocation,
                              self.launch, self.exited | {'monotonic_clock_domain': value}, 'cards-largest')

    @unittest.skipUnless(p.sys.platform == 'darwin', 'Darwin-specific shared clock probe')
    def test_shared_darwin_clock_is_comparable_in_a_fresh_interpreter(self):
        before = p.marker_uptime_ns()
        script = 'import sys;sys.path.insert(0,sys.argv[1]);import diagnostic_postrun as p;print(p.marker_uptime_ns())'
        child = int(p.subprocess.check_output([p.sys.executable, '-c', script, str(Path(__file__).resolve().parent)],
                                             text=True, timeout=5))
        after = p.marker_uptime_ns()
        self.assertLessEqual(before, child)
        self.assertLessEqual(child, after)

    def relocated_fixture(self):
        self.fixture()
        first = p.verify_evidence('cards-largest', collect=True)
        d.write(self.directory / 'postrun.json', first)
        status = dict(self.current, stage='cards-largest', status='success', exit_code=0, deadline=2800)
        d.write(self.build / 'cards-largest-status.json', status)
        checkpoint = dict(self.current, stage='cards-largest', status='success', exit_code=0, errors={},
            deadline=2800, simulator_id=UUID, launch=self.launch,
            summary=summary() | {'startTime': 9.2, 'finishTime': 10.8}, tree=tree(),
            product_test_passed=True, postrun_evidence_complete=True, postrun=first)
        d.write(self.directory / 'verified-result.json', checkpoint)
        stage = 'cards-adaptive'
        directory = self.diag / stage
        launch = dict(self.launch, stage=stage, command=d.test_command('cards', stage),
                      started=12, started_monotonic_ns=120)
        exited = dict(self.exited, stage=stage, launch=launch, finished=14, finished_monotonic_ns=140)
        d.write(directory / 'launch.json', launch)
        d.write(directory / 'exit.json', exited)
        rows = marker_rows()
        session = '22222222-2222-4222-8222-222222222222'
        selector = dict(d.LANES['cards'])[stage]
        for row in rows:
            row.update(pid=124, session_id=session, container_home='/moved',
                test=f'-[DailyWhiskersUITests.SavedCardsTests {selector.split("/")[-1]}]',
                event_wall_time=13, export_wall_time=13.1, event_monotonic_ns='130', export_monotonic_ns='131')
        folder = directory / 'exported/runner'; folder.mkdir(parents=True)
        current = folder / f'cards-124-{session}.jsonl'
        current.write_text(''.join(json.dumps(row) + '\n' for row in rows))
        original = Path(first['marker_evidence']['path'])
        shutil.copyfile(original, folder / original.name)
        export = dict(self.current, status='complete', errors=[], launched_stages=['cards-largest', stage],
                      containers=[], files=[])
        for kind in ('app', 'runner'):
            receipt = directory / f'{kind}-container-metadata.plist'
            receipt.write_bytes(plistlib.dumps({'MCMMetadataIdentifier': kind + '.bundle'}))
            export['containers'].append({'kind': kind, 'bundle_id': kind + '.bundle',
                'path': '/moved' if kind == 'runner' else '/moved-app', 'metadata': str(receipt)})
        for file in folder.glob('*.jsonl'):
            export['files'].append({'kind': 'runner', 'path': str(file),
                'source': '/moved/Documents/ci-diagnostic/' + file.name, 'sha256': p.digest(file)})
        d.write(self.diag / (stage + '-export.json'), export)
        report = dict(self.current, stage=stage, mode='post-run-only', installed=first['installed'])
        d.write(directory / 'postrun.json', report)
        return directory, export, checkpoint, status, original

    def test_relocated_history_keeps_original_successful_container_binding(self):
        directory, export, checkpoint, status, original = self.relocated_fixture()
        result = p.verify_evidence('cards-adaptive', collect=True)
        self.assertEqual(result['status'], 'complete')
        self.assertEqual(result['marker_evidence']['runner_data_container'], '/moved')
        historical = result['historical_marker_evidence']['cards-largest']
        self.assertEqual(historical['original_container'], '/owned')
        self.assertEqual(historical['sha256'], p.digest(original))
        self.assertEqual(historical['pid'], 123)

    def test_relocated_history_requires_successful_same_run_stage_and_checkpoint(self):
        directory, export, checkpoint, status, original = self.relocated_fixture()
        for mutation in [{'status': 'failure'}, {'exit_code': 65}, {'source_sha': 'b' * 40},
                         {'run_attempt': '2'}, {'deadline': 2700}, {'cleanup_errors': ['uncertain']}]:
            d.write(self.build / 'cards-largest-status.json', status | mutation)
            self.assertRaises(ValueError, p.verify_evidence, 'cards-adaptive', collect=True)
        d.write(self.build / 'cards-largest-status.json', status)
        for mutation in [{'status': 'failure'}, {'postrun_evidence_complete': False}, {'run_id': '13'},
                         {'product_test_passed': False}, {'errors': {'verification': 'failed'}}]:
            d.write(self.directory / 'verified-result.json', checkpoint | mutation)
            self.assertRaises(ValueError, p.verify_evidence, 'cards-adaptive', collect=True)

    def test_relocated_changed_pid_session_bytes_or_original_export_fail_closed(self):
        directory, export, checkpoint, status, original = self.relocated_fixture()
        migrated = directory / 'exported/runner' / original.name
        original_bytes = original.read_bytes()
        for key, value in [('pid', 999), ('session_id', '33333333-3333-4333-8333-333333333333'),
                           ('container_home', '/moved'), ('detail', 'changed')]:
            rows = [json.loads(line) for line in original_bytes.splitlines()]
            for row in rows: row[key] = value
            migrated.write_text(''.join(json.dumps(row) + '\n' for row in rows))
            changed = copy.deepcopy(export)
            next(item for item in changed['files'] if item['path'] == str(migrated))['sha256'] = p.digest(migrated)
            d.write(self.diag / 'cards-adaptive-export.json', changed)
            self.assertRaises(ValueError, p.verify_evidence, 'cards-adaptive', collect=True)
        migrated.write_bytes(original_bytes)
        d.write(self.diag / 'cards-adaptive-export.json', export)
        original.write_bytes(original_bytes + b'\n')
        self.assertRaises(ValueError, p.verify_evidence, 'cards-adaptive', collect=True)

    def test_relocated_missing_duplicate_unknown_and_future_history_rejected(self):
        directory, export, checkpoint, status, original = self.relocated_fixture()
        migrated = directory / 'exported/runner' / original.name
        data = migrated.read_bytes()
        migrated.unlink()
        changed = copy.deepcopy(export)
        changed['files'] = [row for row in changed['files'] if row['path'] != str(migrated)]
        d.write(self.diag / 'cards-adaptive-export.json', changed)
        self.assertRaises(ValueError, p.verify_evidence, 'cards-adaptive', collect=True)
        migrated.write_bytes(data)
        d.write(self.diag / 'cards-adaptive-export.json', export | {'launched_stages': ['cards-adaptive', 'cards-largest']})
        self.assertRaises(ValueError, p.verify_evidence, 'cards-adaptive', collect=True)
        for test_name in ('-[Other testUnknown]', '-[DailyWhiskersUITests.SavedCardsTests testAdaptiveCardAndSavedTilesAcrossWindowSizes]'):
            rows = [json.loads(line) for line in data.splitlines()]
            for row in rows: row['test'] = test_name
            migrated.write_text(''.join(json.dumps(row) + '\n' for row in rows))
            changed = copy.deepcopy(export)
            next(item for item in changed['files'] if item['path'] == str(migrated))['sha256'] = p.digest(migrated)
            d.write(self.diag / 'cards-adaptive-export.json', changed)
            self.assertRaises(ValueError, p.verify_evidence, 'cards-adaptive', collect=True)


if __name__ == '__main__':
    unittest.main()

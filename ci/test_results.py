import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from results import collect, gate_summary, render, test_counts

spec = importlib.util.spec_from_file_location('run_stage', Path(__file__).with_name('run-stage.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def fixture(passed=73, failed=0, skipped=0, result='Passed', expected_failures=0):
    return dict(totalTestCount=passed + failed + skipped + expected_failures, passedTests=passed,
                failedTests=failed, skippedTests=skipped, expectedFailures=expected_failures, result=result,
                devicesAndConfigurations=[dict(passedTests=passed + 51, failedTests=failed,
                                               skippedTests=skipped, expectedFailures=expected_failures)])


class ResultTests(unittest.TestCase):
    def test_swift_testing_parameters_are_not_double_counted(self):
        counts = test_counts(fixture())
        self.assertEqual(counts['totalTestCount'], 73)
        self.assertEqual(counts['executions'], 124)
        self.assertTrue(counts['valid_pass'])

    def test_xctest_only_ui_counts(self):
        summary = fixture(3)
        summary['devicesAndConfigurations'][0]['passedTests'] = 3
        self.assertEqual(test_counts(summary)['executions'], 3)

    def test_zero_fail_skip_or_unknown_result_never_pass(self):
        for summary in (fixture(0), fixture(failed=1), fixture(skipped=1), fixture(result='Unknown'),
                        fixture(expected_failures=1), fixture(0, expected_failures=1),
                        fixture(expected_failures=1, result='Expected Failure')):
            with self.subTest(summary=summary):
                self.assertFalse(test_counts(summary)['valid_pass'])

    def test_missing_or_invalid_expected_failure_count_rejected(self):
        missing = fixture()
        del missing['expectedFailures']
        summaries = [missing] + [fixture() | {'expectedFailures': value}
                                 for value in (None, -1, True, 0.0, '0')]
        for summary in summaries:
            with self.subTest(summary=summary), self.assertRaises(ValueError):
                test_counts(summary)

    def test_missing_device_count_keeps_execution_count_unavailable(self):
        summary = fixture()
        del summary['devicesAndConfigurations'][0]['expectedFailures']
        counts = test_counts(summary)
        self.assertIsNone(counts['executions'])
        self.assertTrue(counts['valid_pass'])

    def test_missing_negative_or_inconsistent_counts_rejected(self):
        for change in ({'totalTestCount': 74}, {'passedTests': -1}, {'failedTests': None}, {'passedTests': True}):
            with self.assertRaises(ValueError):
                test_counts(fixture() | change)

    def test_no_results_is_not_zero_tests_or_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.assertFalse(collect(directory))
            text = render(directory)
            self.assertIn('Counts', text.replace('counts', 'Counts'))
            self.assertIn('No result bundle', text)
            self.assertIn('**no**', text)
            self.assertIn('Artifact link unavailable', text)

    def test_full_success_and_failed_process_with_passing_bundle(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for stage in ('prepare', 'resolve', 'unit', 'ui', 'release'):
                (directory / f'{stage}-status.json').write_text(json.dumps({'status': 'success'}))
            for name in ('TestResults', 'SmokeResults'):
                (directory / f'{name}.xcresult').mkdir()
            with patch('results.subprocess.check_output', return_value=json.dumps(fixture())):
                self.assertTrue(collect(directory))
                (directory / 'release-status.json').write_text(json.dumps({'status': 'failure'}))
                self.assertFalse(collect(directory))
            self.assertIn('73 cases', render(directory))
            self.assertIn('124 executions', render(directory))

    def test_expected_failure_evidence_rejected_in_either_suite(self):
        # Synthetic summaries exercise policy, not XCTest/Swift Testing emission.
        for suite in ('unit', 'ui'):
            for passed in (73, 0):
                for missing in (False, True):
                    with self.subTest(suite=suite, passed=passed, missing=missing), tempfile.TemporaryDirectory() as temporary:
                        directory = Path(temporary)
                        for stage in ('prepare', 'resolve', 'unit', 'ui', 'release'):
                            (directory / f'{stage}-status.json').write_text(json.dumps({'status': 'success'}))
                        for name in ('TestResults', 'SmokeResults'):
                            (directory / f'{name}.xcresult').mkdir()
                        summaries = {'unit': fixture(), 'ui': fixture(3)}
                        summaries[suite] = fixture(passed, expected_failures=1)
                        if missing:
                            del summaries[suite]['expectedFailures']
                        raw = [json.dumps(summaries[s]) for s in ('unit', 'ui')]
                        with patch('results.subprocess.check_output', side_effect=raw):
                            self.assertFalse(collect(directory))
                        data = json.loads((directory / 'results.json').read_text())
                        self.assertFalse(data['verified'])
                        text = render(directory)
                        self.assertIn('Evidence complete and passing: **no**', text)
                        if missing:
                            self.assertIn('Unreadable result bundle (ValueError)', text)
                            self.assertNotIn('tests', data['stages'][suite])
                        else:
                            tests = data['stages'][suite]['tests']
                            self.assertFalse(tests['valid_pass'])
                            self.assertEqual(tests['expectedFailures'], 1)
                            self.assertIn(f'{passed} passed, 0 failed, 0 skipped, 1 expected failures', text)

    def test_unreadable_bundle_is_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / 'TestResults.xcresult').mkdir()
            with patch('results.subprocess.check_output', return_value='not json'):
                self.assertFalse(collect(directory))
            self.assertIn('Unreadable result bundle', render(directory))

    def test_running_stage_is_interrupted_not_passed(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / 'unit-status.json').write_text(json.dumps({'status': 'running'}))
            self.assertFalse(collect(directory))
            self.assertIn('interrupted / cancelled', render(directory))

    def test_docs_only_summary(self):
        summary = gate_summary({'classify': {'outputs': {'mode': 'docs'}, 'result': 'success'},
                                'checks': {'result': 'success'}, 'build-and-test': {'result': 'skipped'}})
        self.assertIn('intentionally omitted', summary)
        self.assertIn('No app pass claimed', summary)

    def test_cancelled_and_failed_summary(self):
        for outcome in ('cancelled', 'failure', 'skipped'):
            self.assertIn(outcome, gate_summary({'build-and-test': {'result': outcome}}))

    def test_command_failure_preserved_and_recorded(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.assertEqual(runner.run('unit', ['/bin/sh', '-c', 'exit 23'], directory), 23)
            self.assertEqual(json.loads((directory / 'unit-status.json').read_text())['exit_code'], 23)

    def test_infrastructure_start_failure_recorded(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.assertEqual(runner.run('ui', ['/nonexistent/dw-013-command'], directory), 127)
            self.assertEqual(json.loads((directory / 'ui-status.json').read_text())['status'], 'failure')

    def test_release_scan_rejects_each_smoke_marker(self):
        spec = importlib.util.spec_from_file_location('check_release', Path(__file__).with_name('check-release.py'))
        checker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(checker)
        self.assertTrue(checker.verify(b'normal release binary'))
        for marker in (b'CISmokeMode', b'--ci-smoke', b'Offline CI smoke', b'ci-smoke-offline'):
            self.assertFalse(checker.verify(b'binary prefix' + marker + b'suffix'))

    def test_source_and_tested_merge_identity_distinct(self):
        with patch.dict(os.environ, {'SOURCE_SHA': 'head', 'TESTED_SHA': 'merge'}):
            summary = gate_summary({})
        self.assertIn('Source SHA: `head`', summary)
        self.assertIn('Tested checkout SHA: `merge`', summary)


if __name__ == '__main__':
    unittest.main()

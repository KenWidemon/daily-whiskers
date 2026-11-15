import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import tempfile
import os
import json

spec = importlib.util.spec_from_file_location('pair_evidence', Path(__file__).with_name('evidence.py'))
pair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pair)


class FocusedEvidenceTests(unittest.TestCase):
    def tree(self, result='Passed', identifier=pair.METHOD, target='DailyWhiskersUITests'):
        return {'testNodes': [{'nodeType': 'Test Case', 'nodeIdentifier': identifier,
            'nodeIdentifierURL': 'test://' + target + '/' + identifier[:-2], 'result': result}]}

    def test_pass_and_fail_are_observations(self):
        for result in ('Passed', 'Failed'):
            self.assertEqual(pair.cases(self.tree(result)), result)

    def test_rejects_missing_duplicate_skipped_wrong_method_and_target(self):
        cases = [dict(testNodes=[]), self.tree('Skipped'), self.tree(identifier='SavedCardsTests/testOther()'),
                 self.tree(target='OtherTarget')]
        duplicated = self.tree()
        duplicated['testNodes'] *= 2
        cases.append(duplicated)
        for tree in cases:
            with self.subTest(tree=tree), self.assertRaises(ValueError):
                pair.cases(tree)

    def test_exact_outcome_and_execution_counts(self):
        for result in ('Passed', 'Failed'):
            passed = result == 'Passed'
            counts = dict(totalTestCount=1, executions=1, skippedTests=0, expectedFailures=0,
                          passedTests=int(passed), failedTests=int(not passed), result=result, valid_pass=passed)
            pair.validate_counts(counts, result)
            for key, wrong in [('passedTests', int(not passed)), ('failedTests', int(passed)),
                               ('result', 'Unknown'), ('executions', 2), ('skippedTests', 1)]:
                with self.subTest(result=result, key=key), self.assertRaises(ValueError):
                    pair.validate_counts(dict(counts, **{key: wrong}), result)

    def test_collection_rejects_failed_tree_with_inconsistent_summary(self):
        import sys
        sys.path.insert(0, str(Path('ci').resolve()))
        import results
        import simulator
        import ui_shards
        original = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            try:
                os.chdir(directory)
                Path('build').mkdir()
                for name in ('toolbar-provenance', 'job-budget', 'prepare-status', 'resolve-status',
                             'ui-status', 'simulator', 'cleanup-status'):
                    Path('build', name + '.json').write_text('{}')
                Path('build/toolchain.txt').write_text('fixture')
                counts = dict(totalTestCount=1, executions=1, skippedTests=0, expectedFailures=0,
                              passedTests=1, failedTests=0, result='Unknown', valid_pass=False)
                with patch.object(simulator, 'verify_toolchain'), patch.object(ui_shards, 'device_environment', return_value={}), \
                        patch.object(results, 'test_counts', return_value=counts), \
                        patch.object(results, 'read_xcresult', side_effect=[{}, self.tree('Failed')]):
                    self.assertEqual(pair.collect(), 1)
                data = json.loads(Path('build/toolbar-result.json').read_text())
                self.assertFalse(data['comparison_eligible'])
                self.assertIn('Counts/tree disagreement', data['errors'])
            finally:
                os.chdir(original)

    def receipt(self):
        env = dict(SOURCE_SHA=pair.BASE, TESTED_SHA=pair.BASE, GITHUB_SHA='f' * 40,
                   GITHUB_RUN_ID='1', GITHUB_RUN_ATTEMPT='1', GITHUB_JOB='pair', CI_SHARD_ID='control',
                   ARM='control', PAIR_DEADLINE='1000')
        identity = dict(source_sha=pair.BASE, tested_sha=pair.BASE, run_id='1', run_attempt='1', job='pair', shard='control')
        stage = dict(identity, status='success', exit_code=0, command_exit_code=0, deadline=1000)
        data = {'method_result': 'Passed', 'counts': {'devices': [{'device': {'deviceId': 'owned'}}]},
                'toolbar-provenance': dict(arm='control', source=pair.BASE, workflow='f' * 40, run='1', attempt='1',
                    cache='disabled-fresh-package-directory', lock_sha256='lock',
                    image=dict(ImageOS='macos', ImageVersion='v1', RUNNER_ARCH='ARM64', RUNNER_OS='macOS')),
                'job-budget': dict(identity, execution_seconds=900, deadline=1000),
                'prepare-status': dict(stage), 'resolve-status': dict(stage), 'ui-status': dict(stage),
                'simulator': dict(identity, status='ready', readback_verified=True, simulator_id='owned', ownership='created'),
                'cleanup-status': dict(identity, status='success', readback_verified=True,
                    simulator_id='owned', ownership='created', operation='delete-owned')}
        return data, env

    def test_receipt_accepts_pass_and_completed_failure(self):
        data, env = self.receipt()
        pair.validate(data, env, 'lock')
        data['method_result'] = 'Failed'
        data['ui-status'].update(status='failure', exit_code=65, command_exit_code=65)
        pair.validate(data, env, 'lock')

    def test_receipt_rejects_incomplete_or_mismatched_evidence(self):
        changes = [('toolbar-provenance', 'source', 'stale'), ('toolbar-provenance', 'cache', 'warm'),
                   ('job-budget', 'deadline', 1200), ('job-budget', 'execution_seconds', 3000),
                   ('prepare-status', 'status', 'failure'), ('resolve-status', 'source_sha', 'stale'),
                   ('ui-status', 'status', 'timed_out'), ('ui-status', 'exit_code', 124),
                   ('ui-status', 'command_exit_code', 65), ('ui-status', 'cleanup_errors', ['denied']),
                   ('cleanup-status', 'readback_verified', False), ('cleanup-status', 'simulator_id', 'other'),
                   ('cleanup-status', 'ownership', 'preexisting'), ('simulator', 'status', 'failed')]
        for section, key, value in changes:
            data, env = self.receipt()
            data[section][key] = value
            with self.subTest(section=section, key=key), self.assertRaises(ValueError):
                pair.validate(data, env, 'lock')
        data, env = self.receipt()
        with self.assertRaises(ValueError):
            pair.validate(data, env, 'changed-lock')

    def test_provenance_rejects_wrong_context_before_reading_source(self):
        environment = dict(ARM='control', GITHUB_EVENT_NAME='workflow_dispatch',
            GITHUB_REPOSITORY='KenWidemon/daily-whiskers', GITHUB_RUN_ATTEMPT='1', GITHUB_REF='refs/heads/codex/pr143-toolbar-pair-design')
        for key, value in [('ARM', 'other'), ('GITHUB_EVENT_NAME', 'push'),
                           ('GITHUB_REPOSITORY', 'other/repo'), ('GITHUB_RUN_ATTEMPT', '2'), ('GITHUB_REF', 'refs/heads/codex/develop')]:
            with self.subTest(key=key), patch.dict(os.environ, dict(environment, **{key: value}), clear=True), \
                    self.assertRaises(ValueError):
                pair.provenance()

    def test_provenance_rejects_wrong_source_and_unreviewed_candidate(self):
        environment = dict(ARM='control', GITHUB_EVENT_NAME='workflow_dispatch',
            GITHUB_REPOSITORY='KenWidemon/daily-whiskers', GITHUB_RUN_ATTEMPT='1', GITHUB_SHA='f' * 40, GITHUB_REF='refs/heads/codex/pr143-toolbar-pair-design')
        with patch.dict(os.environ, environment, clear=True), patch.object(pair, 'git', return_value='wrong'), \
                self.assertRaises(ValueError):
            pair.provenance()
        environment['ARM'] = 'treatment'
        with patch.dict(os.environ, environment, clear=True), patch.object(pair, 'git', side_effect=['f' * 40, 'f' * 40, 'unreviewed.swift']), \
                self.assertRaises(ValueError):
            pair.provenance()

    def test_collection_writes_failure_receipt_when_bundle_unreadable(self):
        import sys
        sys.path.insert(0, str(Path('ci').resolve()))
        import results
        import simulator
        original = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            try:
                os.chdir(directory)
                Path('build').mkdir()
                Path('build/toolchain.txt').write_text('fixture')
                with patch.object(simulator, 'verify_toolchain'), \
                        patch.object(results, 'read_xcresult', side_effect=ValueError('unreadable')):
                    self.assertEqual(pair.collect(), 1)
                data = json.loads(Path('build/toolbar-result.json').read_text())
                self.assertFalse(data['comparison_eligible'])
                self.assertIn('unreadable', data['errors'])
            finally:
                os.chdir(original)

    def test_original_method_and_timeout_are_preserved(self):
        script = Path(__file__).with_name('run.sh').read_text()
        self.assertIn('-only-testing:DailyWhiskersUITests/' + pair.METHOD[:-2], script)
        self.assertEqual(script.count('-only-testing:'), 1)
        for value in ('-default-test-execution-time-allowance 720',
                      '-maximum-test-execution-time-allowance 720', '-parallel-testing-enabled NO'):
            self.assertIn(value, script)
        self.assertNotIn('retry', script)

    def test_workflow_is_manual_only_two_arms(self):
        workflow = Path('.github/workflows/ios.yml').read_text()
        self.assertIn('workflow_dispatch:', workflow)
        self.assertNotIn('pull_request:', workflow)
        self.assertNotIn('push:', workflow)
        self.assertIn('arm: [control, treatment]', workflow)
        self.assertIn('timeout-minutes: 60', workflow)
        self.assertIn('time.time()+2700', workflow)
        self.assertIn('PAIR_DEADLINE', workflow)
        self.assertNotIn('GITHUB_WORKSPACE:', workflow)
        self.assertNotIn('actions/cache', workflow)
        self.assertIn('retention-days: 30', workflow)


if __name__ == '__main__':
    unittest.main()

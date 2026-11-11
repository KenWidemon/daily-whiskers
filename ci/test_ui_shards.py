import copy
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import ui_shards as shards
from results import collect
from test_results import fixture

DEVICE = dict(deviceName='iPhone 17 Pro', modelName='iPhone 17 Pro', osVersion='26.4.1',
              osBuildNumber='23E254a', architecture='arm64', platform='iOS Simulator')
ENV = dict(SOURCE_SHA='a'*40, TESTED_SHA='b'*40, GITHUB_SHA='b'*40,
           GITHUB_RUN_ID='123', GITHUB_RUN_ATTEMPT='1', GITHUB_REPOSITORY='KenWidemon/daily-whiskers')


def summary(count):
    data = fixture(count)
    data['devicesAndConfigurations'][0].update(passedTests=count, device=DEVICE)
    return data


def tree(identifiers):
    return {'testNodes': [{'nodeType': 'Test Plan', 'children': [
        {'nodeType': 'Test Case', 'nodeIdentifier': name, 'result': 'Passed',
         'nodeIdentifierURL': 'test://com.apple.xcode/DailyWhiskers/DailyWhiskersUITests/' + name[:-2]}
        for name in identifiers]}]}


class ShardTests(unittest.TestCase):
    def make_records(self, directory):
        data = shards.inventory()
        for part in shards.PARTS:
            target = directory / part
            target.mkdir()
            for stage in shards.stages_for(part):
                (target / f'{stage}-status.json').write_text(json.dumps(dict(status='success', exit_code=0, stage=stage,
                    source_sha=ENV['SOURCE_SHA'], tested_sha=ENV['TESTED_SHA'], run_id=ENV['GITHUB_RUN_ID'],
                    run_attempt=ENV['GITHUB_RUN_ATTEMPT'],
                    job='build-and-test' if part == 'unit-release' else 'ui-shards', shard=part)))
            (target / 'toolchain.txt').write_text('Xcode 26.6\nBuild version 17F113\nSwift 6.3.3\n26.5')
            tests = [] if part == 'unit-release' else shards.expected_tests(data, part)
            bundle = 'TestResults.xcresult' if part == 'unit-release' else f'SmokeResults-{part}.xcresult'
            (target / bundle).mkdir()
            responses = [json.dumps(summary(210 if part == 'unit-release' else len(tests)))]
            if tests:
                responses.append(json.dumps(tree(tests)))
            with patch.dict(os.environ, ENV), patch('results.subprocess.check_output', side_effect=responses):
                self.assertTrue(collect(target, part))

    def test_current_complete_inventory_preserves_all_five_required_classes(self):
        data = shards.inventory()
        self.assertEqual(set(sum(data['shards'].values(), [])), {'RegressionSmokeTests', 'SavedCardsTests',
            'SavedCardsLoadStateTests', 'StillnessModeTests', 'ReminderUITests'})
        self.assertEqual(data['shards'], {
            'cards': ['SavedCardsTests'],
            'settings': ['RegressionSmokeTests', 'StillnessModeTests'],
            'reminders': ['ReminderUITests', 'SavedCardsLoadStateTests'],
        })
        self.assertEqual({p: len(shards.expected_tests(data, p)) for p in shards.SHARDS},
                         {'cards': 7, 'settings': 8, 'reminders': 12})
        self.assertEqual(sum(len(shards.expected_tests(data, p)) for p in shards.SHARDS), 27)
        self.assertEqual(set(data['optional']), {'AuthLayoutTests', 'BonusCardTests', 'DailyCardSharingTests'})

    def test_inventory_rejects_missing_duplicate_unknown_and_source_drift(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(shards.ROOT / 'DailyWhiskersUITests', root / 'DailyWhiskersUITests')
            (root / 'ci').mkdir()
            original = shards.inventory()
            mutations = [lambda d: d['shards']['cards'].pop(),
                         lambda d: d['shards']['cards'].append('ReminderUITests'),
                         lambda d: d['shards']['cards'].append('Unknown'),
                         lambda d: d['classes']['ReminderUITests'].pop(),
                         lambda d: d['classes']['ReminderUITests'].append('testUnknown'),
                         lambda d: d['optional'].update(ReminderUITests='excluded'),
                         lambda d: d['shards'].update(unknown=['ReminderUITests'])]
            for mutate in mutations:
                data = copy.deepcopy(original); mutate(data)
                (root / 'ci/ui-inventory.json').write_text(json.dumps(data))
                with self.assertRaises(ValueError):
                    shards.inventory(root)
            (root / 'ci/ui-inventory.json').write_text(json.dumps(original))
            (root / 'DailyWhiskersUITests/Nested').mkdir()
            (root / 'DailyWhiskersUITests/Nested/NewTests.swift').write_text('final class NewTests: XCTestCase { func testNew() {} }')
            with self.assertRaises(ValueError):
                shards.inventory(root)

    def test_real_shell_command_selects_every_class_once_without_skips(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ('ci', 'DailyWhiskersUITests'):
                shutil.copytree(shards.ROOT / name, root / name)
            lock = root / 'DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
            lock.parent.mkdir(parents=True); lock.write_text('test lock')
            (root / 'Package.resolved.expected').write_text('test lock')
            executable = root / 'xcodebuild'
            executable.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$GITHUB_WORKSPACE/arguments"\n')
            executable.chmod(0o755)
            env = dict(os.environ, PATH=str(root)+os.pathsep+os.environ['PATH'], GITHUB_WORKSPACE=str(root),
                       RUNNER_TEMP=str(root), SIMULATOR_ID='synthetic')
            selections = []
            for part in shards.SHARDS:
                subprocess.run(['bash', 'ci/test-app.sh', 'ui'], cwd=root, env=dict(env, CI_PART=part), check=True)
                args = (root / 'arguments').read_text().splitlines()
                selected = [arg for arg in args if arg.startswith('-only-testing:')]
                self.assertEqual(selected, ['-only-testing:DailyWhiskersUITests/'+n for n in shards.inventory()['shards'][part]])
                self.assertFalse(any(arg.startswith('-skip-testing') for arg in args))
                self.assertIn('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING', args)
                self.assertEqual(args[args.index('-parallel-testing-enabled')+1], 'NO')
                self.assertEqual(args[args.index('-resultBundlePath')+1], f'build/SmokeResults-{part}.xcresult')
                selections += selected
            self.assertEqual(len(selections), len(set(selections)))
            (root / 'arguments').unlink()
            failed = subprocess.run(['bash', 'ci/test-app.sh', 'ui'], cwd=root, env=dict(env, CI_PART='unknown'), capture_output=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertFalse((root / 'arguments').exists())

    def test_successful_collect_and_aggregate(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, ENV):
            directory = Path(tmp); self.make_records(directory)
            self.assertEqual(len(shards.aggregate(directory)), 4)

    def test_aggregate_rejects_incomplete_failed_cancelled_or_mismatched_evidence(self):
        changes = [lambda d: d.update(verified=False), lambda d: d.update(part='unknown'),
                   lambda d: d.update(inventory_sha256='stale'), lambda d: d.update(required_tests=[]),
                   lambda d: d.update(observed_tests=[]),
                   lambda d: d['observed_tests'].append(d['observed_tests'][0]),
                   lambda d: d['stages'].pop('prepare'),
                   lambda d: d['stages']['ui'].update(exit_code=65),
                   lambda d: d['stages']['ui']['tests'].update(totalTestCount=0),
                   lambda d: d['environment'].update(toolchain='different')]
        changes += [lambda d, k=k: d['stages']['ui'].update({k: 'stale'})
                    for k in ('stage', 'source_sha', 'tested_sha', 'run_id', 'run_attempt', 'job', 'shard')]
        changes += [lambda d, k=k: d['stages']['ui'].pop(k)
                    for k in ('stage', 'source_sha', 'tested_sha', 'run_id', 'run_attempt', 'job', 'shard')]
        changes += [lambda d, k=k: d['identity'].update({k:'wrong'}) for k in shards.IDENTITY_KEYS]
        changes += [lambda d, s=s: d['stages']['ui'].update(status=s)
                    for s in ('failure', 'timed_out', 'cancelled', 'skipped', 'running', 'not run')]
        changes += [lambda d, k=k: d['stages']['ui']['tests'].update({k:1})
                    for k in ('failedTests', 'skippedTests', 'expectedFailures')]
        changes += [lambda d, k=k: d['environment']['device'].update({k:'different'}) for k in shards.DEVICE_KEYS]
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, ENV):
            directory = Path(tmp); self.make_records(directory)
            path = directory / 'cards/results.json'; original = json.loads(path.read_text())
            for change in changes:
                data = copy.deepcopy(original); change(data); path.write_text(json.dumps(data))
                with self.subTest(data=data), self.assertRaises((ValueError, KeyError)):
                    shards.aggregate(directory)
            path.unlink()
            with self.assertRaises(ValueError): shards.aggregate(directory)
            path.write_text('not json')
            with self.assertRaises(ValueError): shards.aggregate(directory)
            path.write_text(json.dumps(original))
            shutil.copytree(directory/'cards', directory/'duplicate')
            with self.assertRaises(ValueError): shards.aggregate(directory)

    def test_case_tree_rejects_bad_status_wrong_target_duplicate_and_missing(self):
        identifiers = shards.expected_tests(shards.inventory(), 'settings')
        self.assertEqual(shards.test_identifiers(tree(identifiers)), identifiers)
        for change in (lambda d: d['testNodes'].clear(),
                       lambda d: d['testNodes'][0]['children'].append(d['testNodes'][0]['children'][0]),
                       lambda d: d['testNodes'][0]['children'][0].update(result='Skipped'),
                       lambda d: d['testNodes'][0]['children'][0].update(nodeIdentifierURL='wrong target'),
                       lambda d: d['testNodes'][0]['children'][0].update(nodeIdentifier='unknown')):
            data=tree(identifiers); change(data)
            with self.assertRaises(ValueError): shards.test_identifiers(data)

    def test_collector_rejects_partial_but_passing_test_tree(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, ENV):
            directory=Path(tmp); self.make_records(directory)
            target=directory/'settings'
            identifiers=shards.expected_tests(shards.inventory(), 'settings')[:-1]
            with patch('results.subprocess.check_output', side_effect=[json.dumps(summary(len(identifiers))), json.dumps(tree(identifiers))]):
                self.assertFalse(collect(target, 'settings'))
            self.assertIn('Missing/unknown UI tests', (target/'results.json').read_text())

    def test_collector_cannot_relabel_stale_stage_as_current_evidence(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, ENV):
            directory = Path(tmp); self.make_records(directory)
            target = directory / 'cards'
            status = json.loads((target / 'ui-status.json').read_text())
            status.update(source_sha='c' * 40, shard='reminders')
            (target / 'ui-status.json').write_text(json.dumps(status))
            identifiers = shards.expected_tests(shards.inventory(), 'cards')
            with patch('results.subprocess.check_output', side_effect=[json.dumps(summary(len(identifiers))),
                       json.dumps(tree(identifiers))]):
                self.assertFalse(collect(target, 'cards'))
            record = json.loads((target / 'results.json').read_text())
            self.assertFalse(record['verified'])
            self.assertIn('stage evidence', record['evidence_error'])

    def test_hung_shard_tree_reader_is_bounded_and_writes_failed_manifest(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, ENV):
            directory = Path(tmp); self.make_records(directory)
            target = directory / 'cards'
            count = len(shards.expected_tests(shards.inventory(), 'cards'))
            with patch('results.subprocess.check_output', side_effect=[json.dumps(summary(count)),
                       subprocess.TimeoutExpired('xcresulttool tests', 45)]) as reader:
                self.assertFalse(collect(target, 'cards'))
            self.assertEqual([call.kwargs['timeout'] for call in reader.call_args_list], [45, 45])
            record = json.loads((target / 'results.json').read_text())
            self.assertFalse(record['verified'])
            self.assertIn('timed out', record['evidence_error'])
            with self.assertRaises(ValueError):
                shards.aggregate(directory)

    def test_timed_out_shard_with_passing_bundle_is_rejected_end_to_end(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, ENV):
            directory = Path(tmp); self.make_records(directory)
            target = directory / 'reminders'
            status = json.loads((target / 'ui-status.json').read_text())
            status.update(status='timed_out', exit_code=124, command_exit_code=0)
            (target / 'ui-status.json').write_text(json.dumps(status))
            identifiers = shards.expected_tests(shards.inventory(), 'reminders')
            with patch('results.subprocess.check_output', side_effect=[json.dumps(summary(len(identifiers))),
                       json.dumps(tree(identifiers))]):
                self.assertFalse(collect(target, 'reminders'))
            record = json.loads((target / 'results.json').read_text())
            self.assertEqual(record['part'], 'reminders')
            self.assertEqual(record['identity'], ENV)
            self.assertTrue(record['stages']['ui']['tests']['valid_pass'])
            self.assertFalse(record['verified'])
            with self.assertRaises(ValueError):
                shards.aggregate(directory)

    def test_workflow_matrix_and_gate_remain_complete(self):
        workflow=(shards.ROOT/'.github/workflows/ios.yml').read_text()
        self.assertIn('shard: ['+', '.join(shards.SHARDS)+']', workflow)
        self.assertIn('fail-fast: false', workflow)
        self.assertIn('needs: [classify, checks, build-and-test, ui-shards]', workflow)
        self.assertIn('name: CI Gate', workflow)
        self.assertIn('python3 ci/ui_shards.py aggregate', workflow)
        self.assertNotIn('continue-on-error', workflow)
        self.assertNotIn('merge-multiple: true', workflow)


if __name__ == '__main__':
    unittest.main()

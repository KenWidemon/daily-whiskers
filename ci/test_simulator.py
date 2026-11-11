"""Offline destination/lifecycle proofs. All simctl commands are mocked."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import re
from unittest.mock import Mock, patch

import simulator as sim

IDENTIFIER = '11111111-1111-4111-8111-111111111111'
OTHER_ID = '22222222-2222-4222-8222-222222222222'
TOOLCHAIN = (f'Developer directory: {sim.DEVELOPER_DIR}\nArchitecture: arm64\n'
             'Xcode 27.2\nBuild version 27B52\nApple Swift version 6.4 (synthetic fixture)\nSimulator SDK: 27.2')


def runtime():
    return dict(identifier=sim.RUNTIME, version=sim.VERSION, buildversion=sim.BUILD, platform='iOS',
                isAvailable=True, supportedArchitectures=['arm64'], supportedDeviceTypes=[{'identifier': sim.DEVICE_TYPE}])


def device(identifier=IDENTIFIER, **changes):
    return dict(udid=identifier, name=sim.NAME, deviceTypeIdentifier=sim.DEVICE_TYPE,
                isAvailable=True, state='Shutdown') | changes


def devices(*items):
    return {'devices': {sim.RUNTIME: list(items)}}


def preparation(identity, ownership='preexisting'):
    return dict(identity, status='ready', ownership=ownership, runtime=sim.RUNTIME,
                version=sim.VERSION, build=sim.BUILD, architecture='arm64', device_type=sim.DEVICE_TYPE,
                name=sim.NAME, simulator_id=IDENTIFIER, readback_verified=True,
                preexisting_ids=[IDENTIFIER] if ownership == 'preexisting' else [])


class SimulatorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.environment = patch.dict(os.environ, {
            'GITHUB_ENV': str(self.directory / 'env'), 'SOURCE_SHA': 'a' * 40, 'TESTED_SHA': 'b' * 40,
            'GITHUB_RUN_ID': '123', 'GITHUB_RUN_ATTEMPT': '1', 'GITHUB_JOB': 'ui-shards', 'CI_SHARD_ID': 'cards'})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def record(self, name='simulator.json'):
        return json.loads((self.directory / name).read_text())

    def test_toolchain_rejects_old_wrong_missing_and_conflicting_pins(self):
        sim.verify_toolchain(TOOLCHAIN)
        for before, after in (('27.2', '26.6'), ('27B52', '17F113'), ('arm64', 'x86_64'),
                              ('Apple Swift version', 'unknown'), ('Simulator SDK: 27.2', '')):
            with self.subTest(before=before), self.assertRaises(ValueError):
                sim.verify_toolchain(TOOLCHAIN.replace(before, after))
        with self.assertRaises(ValueError):
            sim.verify_toolchain(TOOLCHAIN + '\nXcode 26.6')

    def test_runtime_requires_every_exact_compatibility_field(self):
        sim.exact_runtime({'runtimes': [runtime()]})
        changes = dict(identifier=sim.RUNTIME + '-1', version='27.1', buildversion='24B99',
                       platform='tvOS', isAvailable=False, supportedArchitectures=['x86_64'], supportedDeviceTypes=[])
        for key, value in changes.items():
            for remove in (False, True):
                item = runtime()
                if remove:
                    item.pop(key)
                else:
                    item[key] = value
                with self.subTest(key=key, remove=remove), self.assertRaises(ValueError):
                    sim.exact_runtime({'runtimes': [item]})
        with self.assertRaises(ValueError):
            sim.exact_runtime({'runtimes': [runtime(), runtime()]})

    def test_preexisting_exact_device_is_selected_and_never_mutated_by_lifecycle(self):
        fake = Mock(side_effect=[json.dumps({'runtimes': [runtime()]}),
                                 json.dumps(devices(device())), json.dumps(devices(device()))])
        self.assertEqual(sim.prepare(self.directory, fake), 0)
        self.assertEqual(self.record()['ownership'], 'preexisting')
        self.assertEqual((self.directory / 'env').read_text(), f'SIMULATOR_ID={IDENTIFIER}\n')
        fake = Mock(return_value=json.dumps(devices(device(state='Booted'))))
        self.assertEqual(sim.cleanup(self.directory, fake), 0)
        self.assertEqual(fake.call_args_list[0].args, ('list', 'devices', '--json'))
        self.assertEqual(fake.call_count, 1)
        self.assertEqual(self.record('cleanup-status.json')['operation'], 'preserved-preexisting')

    def test_absent_device_is_created_read_back_and_owned_cleanup_is_verified(self):
        def creation(*args):
            # Provenance must be durable before the mutating command.
            self.assertEqual(self.record()['ownership'], 'uncertain')
            self.assertEqual(self.record()['status'], 'creating')
            return IDENTIFIER
        fake = Mock(side_effect=[json.dumps({'runtimes': [runtime()]}), json.dumps(devices()),
                                 IDENTIFIER, json.dumps(devices(device()))])
        def call(*args):
            if args[0] == 'create':
                creation(*args)
            return fake(*args)
        self.assertEqual(sim.prepare(self.directory, call), 0)
        self.assertEqual(fake.call_args_list[2].args, ('create', sim.NAME, sim.DEVICE_TYPE, sim.RUNTIME))
        self.assertEqual(self.record()['ownership'], 'created')
        fake = Mock(side_effect=[json.dumps(devices(device(state='Booted'))), '', '', json.dumps(devices())])
        self.assertEqual(sim.cleanup(self.directory, fake), 0)
        self.assertEqual([call.args for call in fake.call_args_list], [
            ('list', 'devices', '--json'), ('shutdown', IDENTIFIER), ('delete', IDENTIFIER), ('list', 'devices', '--json')])
        self.assertTrue(self.record('cleanup-status.json')['readback_verified'])

    def test_ambiguous_preexisting_devices_fail_without_creation(self):
        fake = Mock(side_effect=[json.dumps({'runtimes': [runtime()]}),
                                 json.dumps(devices(device(), device(OTHER_ID)))])
        self.assertEqual(sim.prepare(self.directory, fake), 1)
        self.assertEqual(fake.call_count, 2)
        self.assertEqual(self.record()['ownership'], 'none')
        self.assertFalse((self.directory / 'env').exists())

    def test_wrong_runtime_never_reaches_create_or_fallback(self):
        fake = Mock(return_value=json.dumps({'runtimes': [runtime() | {'buildversion': 'wrong'}]}))
        self.assertEqual(sim.prepare(self.directory, fake), 1)
        self.assertEqual(fake.call_count, 1)

    def test_create_timeout_invalid_uuid_and_reused_uuid_preserve_uncertainty(self):
        for response in (subprocess.TimeoutExpired('simctl create', 20), 'invalid', OTHER_ID):
            with self.subTest(response=response):
                path = self.directory / 'simulator.json'
                if path.exists():
                    path.unlink()
                fake = Mock(side_effect=[json.dumps({'runtimes': [runtime()]}),
                                         json.dumps(devices(device(OTHER_ID, name='Different name'))), response])
                self.assertEqual(sim.prepare(self.directory, fake), 1)
                self.assertEqual(self.record()['ownership'], 'uncertain')
                cleanup = Mock()
                self.assertEqual(sim.cleanup(self.directory, cleanup), 1)
                cleanup.assert_not_called()
                self.assertFalse(self.record('cleanup-status.json')['readback_verified'])

    def test_failed_post_create_readback_keeps_owned_uuid_for_cleanup(self):
        fake = Mock(side_effect=[json.dumps({'runtimes': [runtime()]}), json.dumps(devices()),
                                 IDENTIFIER, subprocess.TimeoutExpired('simctl list', 20)])
        self.assertEqual(sim.prepare(self.directory, fake), 1)
        self.assertEqual(self.record()['simulator_id'], IDENTIFIER)
        self.assertEqual(self.record()['ownership'], 'created')
        fake = Mock(side_effect=[json.dumps(devices(device())), '', json.dumps(devices())])
        self.assertEqual(sim.cleanup(self.directory, fake), 0)
        self.assertNotIn(('shutdown', IDENTIFIER), [call.args for call in fake.call_args_list])

    def test_stale_and_preexisting_ownership_never_authorize_delete(self):
        for mutation in ({'run_attempt': '2'}, {'preexisting_ids': [IDENTIFIER]}):
            sim.write(self.directory / 'simulator.json', preparation(sim.identity(), 'created') | mutation)
            fake = Mock(return_value=json.dumps(devices(device())))
            self.assertEqual(sim.cleanup(self.directory, fake), 1)
            self.assertTrue(all(call.args[0] == 'list' for call in fake.call_args_list))

    def test_missing_unknown_changed_or_unremoved_device_cannot_pass_cleanup(self):
        cases = [[json.dumps(devices())],
                 [json.dumps(devices(device(deviceTypeIdentifier='wrong')))],
                 [json.dumps(devices(device())), subprocess.CalledProcessError(1, 'simctl delete')],
                 [json.dumps(devices(device())), subprocess.TimeoutExpired('simctl delete', 20)],
                 [json.dumps(devices(device())), '', json.dumps(devices(device()))]]
        for responses in cases:
            sim.write(self.directory / 'simulator.json', preparation(sim.identity(), 'created'))
            fake = Mock(side_effect=responses)
            self.assertEqual(sim.cleanup(self.directory, fake), 1)
            record = self.record('cleanup-status.json')
            self.assertEqual(record['status'], 'failure')
            self.assertFalse(record['readback_verified'])
            self.assertLessEqual(sum(call.args[0] == 'delete' for call in fake.call_args_list), 1)

    def test_missing_record_and_unknown_creation_remain_visible(self):
        fake = Mock()
        self.assertEqual(sim.cleanup(self.directory, fake), 1)
        fake.assert_not_called()
        record = preparation(sim.identity()) | {'ownership': 'uncertain', 'status': 'creating'}
        sim.write(self.directory / 'simulator.json', record)
        self.assertEqual(sim.cleanup(self.directory, fake), 1)
        fake.assert_not_called()

    def test_prepare_cannot_reset_existing_ownership(self):
        sim.write(self.directory / 'simulator.json', preparation(sim.identity()))
        fake = Mock()
        with self.assertRaises(ValueError):
            sim.prepare(self.directory, fake)
        fake.assert_not_called()

    def test_all_cleanup_commands_share_one_45_second_deadline_without_retries(self):
        with patch('simulator.time.monotonic', side_effect=[100, 101, 130, 146]), \
             patch('simulator.subprocess.check_output', return_value='ok') as command:
            client = sim.Simctl(45)
            client('list', 'devices', '--json')
            client('delete', IDENTIFIER)
            with self.assertRaises(ValueError):
                client('list', 'devices', '--json')
            self.assertEqual([c.kwargs['timeout'] for c in command.call_args_list], [20, 15])

    def test_workflow_uses_preview_exact_toolchain_and_distinct_dependency_caches(self):
        root = Path(__file__).resolve().parent.parent
        workflow = (root / '.github/workflows/ios.yml').read_text()
        jobs = dict(re.findall(r'^  ([\w-]+):\n(.*?)(?=^  [\w-]+:|\Z)', workflow, re.M | re.S))
        for job in ('build-and-test', 'ui-shards'):
            block = jobs[job]
            self.assertIn('    runs-on: xcode-27\n', block)
            self.assertIn(f'      DEVELOPER_DIR: {sim.DEVELOPER_DIR}\n', block)
            self.assertIn('-xcode-27.2-27B52-iphonesimulator-27.2-', block)
            self.assertNotIn('restore-keys:', block)
            self.assertNotIn('xcode-26.', block)
        config = (root / '.github/actionlint.yaml').read_text()
        self.assertEqual(re.findall(r'^    - (.+)$', config, re.M), ['xcode-27'])
        self.assertNotIn('ignore:', config)
        script = (root / 'ci/prepare-app.sh').read_text()
        self.assertIn('python3 ci/simulator.py verify-toolchain', script)
        self.assertIn('python3 ci/simulator.py prepare', script)
        self.assertNotIn('xcode-select', script)

    def test_legacy_runtime_and_wrong_supported_type_shapes_are_rejected(self):
        for change in ({'version': '26.4.1', 'buildversion': '23E254a'},
                       {'supportedArchitectures': 'arm64'}, {'supportedDeviceTypes': [sim.DEVICE_TYPE]},
                       {'supportedDeviceTypes': sim.DEVICE_TYPE}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                sim.exact_runtime({'runtimes': [runtime() | change]})


if __name__ == '__main__':
    unittest.main()

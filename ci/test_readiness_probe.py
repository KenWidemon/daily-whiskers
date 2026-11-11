"""Offline synthetic Apple-tool fixtures; imports never execute Apple commands."""
import copy
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

import readiness_probe as probe
from probe_supervisor import CommandFailure, write

UUID = '11111111-1111-4111-8111-111111111111'
OTHER = '22222222-2222-4222-8222-222222222222'
SHA = 'a' * 40
ENV = {'EXPECTED_SOURCE_SHA': SHA, 'GITHUB_SHA': SHA, 'GITHUB_RUN_ID': '12345',
       'GITHUB_RUN_ATTEMPT': '1', 'GITHUB_REF': probe.REF,
       'GITHUB_REPOSITORY': 'KenWidemon/daily-whiskers', 'GITHUB_JOB': 'readiness-probe',
       'GITHUB_EVENT_NAME': 'workflow_dispatch', 'DEVELOPER_DIR': probe.DEVELOPER_DIR,
       'RUNNER_ARCH': 'ARM64', 'ImageOS': 'macos27', 'ImageVersion': '20261104.0337.1',
       'PROBE_OUTCOME': 'success', 'CLEANUP_OUTCOME': 'success', 'ARTIFACT_OUTCOME': 'success'}


def runtime_fixture():
    return {'runtimes': [{'identifier': probe.RUNTIME, 'version': '27.2',
                          'buildversion': '24B8117', 'isAvailable': True, 'platform': 'iOS',
                          'supportedArchitectures': ['arm64'],
                          'supportedDeviceTypes': [{'identifier': probe.DEVICE_TYPE}]}]}


def device_fixture(state='Shutdown'):
    return {'devices': {probe.RUNTIME: [{'udid': UUID, 'name': 'DW-readiness-12345-1',
                                         'deviceTypeIdentifier': probe.DEVICE_TYPE,
                                         'isAvailable': True, 'state': state}]}}


class MockRun:
    def __init__(self, replacements=None):
        self.calls = []
        self.commands = []
        self.now = 100
        self.clock = lambda: self.now
        self.deadline = 700
        self.answers = {
            'tested-sha': SHA, 'architecture': 'arm64', 'host-version': '27.0.1', 'host-build': '26A434',
            'xcode-version': 'Xcode 27.2\nBuild version 27B52', 'sdk-version': '27.2',
            'swift-version': 'Apple Swift version 6.3', 'runtimes': json.dumps(runtime_fixture()),
            'devices-before': '{"devices": {}}', 'create': UUID,
            'devices-prepared': json.dumps(device_fixture()),
            'devices-booted': json.dumps(device_fixture('Booted')),
            'cleanup-before': json.dumps(device_fixture('Booted')),
            'cleanup-after': '{"devices": {}}', 'service-pids': ''}
        self.answers.update(replacements or {})

    def run(self, name, argv, timeout=10, **kwargs):
        self.calls.append((name, argv, timeout, kwargs))
        record = {'name': name, 'status': 'success', 'pid': 123, 'pgid': 123,
                  'reaped': True, 'group_absent': True, 'exit_code': 0,
                  'exec_attempt_observed': True, 'launch_authorized': True, 'output_truncated': False}
        self.commands.append(record)
        value = self.answers.get(name, 'fixture')
        if kwargs.get('absolute_deadline') is not None and self.clock() >= kwargs['absolute_deadline']:
            record.update(status='not_started', pid=None, launch_authorized=False)
            value = CommandFailure('Deadline passed; no launch')
        elif isinstance(value, Exception):
            record.update(status='failure', exit_code=1)
        phase = ('run' if name in probe.RUN_COMMANDS else 'cleanup'
                 if name in ('cleanup-before', 'shutdown', 'delete', 'cleanup-after') else 'collect')
        write(self.directory / f'{phase}-{len(self.commands):02d}-{name}.json', record)
        if isinstance(value, Exception):
            raise value
        return value


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        MockRun.directory = self.root

    def prepare(self, replacements=None):
        for path in self.root.iterdir():
            path.unlink()
        run = MockRun(replacements)
        code = probe.execute(self.root, run, ENV)
        probe.collect(self.root, MockRun(), ENV)
        return code, run, probe.read(self.root / 'probe.json')

    def test_exact_runtime_accepts_only_supported_full_identity(self):
        self.assertEqual(probe.runtime(runtime_fixture())['buildversion'], '24B8117')
        mutations = {'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4',
                     'version': '27.0', 'buildversion': '24B91016s', 'isAvailable': False,
                     'platform': 'tvOS', 'supportedArchitectures': ['x86_64'],
                     'supportedDeviceTypes': [{'identifier': 'com.apple.CoreSimulator.SimDeviceType.iPhone-Duo'}]}
        for key, value in mutations.items():
            with self.subTest(key=key):
                fixture = runtime_fixture()
                fixture['runtimes'][0][key] = value
                with self.assertRaises(ValueError):
                    probe.runtime(fixture)
        for values in ([], runtime_fixture()['runtimes'] * 2):
            with self.assertRaises(ValueError):
                probe.runtime({'runtimes': values})

    def test_identity_rejects_every_changed_boundary_before_commands(self):
        mutations = {'GITHUB_SHA': 'b' * 40, 'EXPECTED_SOURCE_SHA': 'main',
                     'GITHUB_REF': 'refs/heads/main', 'GITHUB_RUN_ATTEMPT': '2',
                     'GITHUB_REPOSITORY': 'other/repo', 'GITHUB_JOB': 'build-and-test',
                     'GITHUB_EVENT_NAME': 'push', 'GITHUB_RUN_ID': None,
                     'DEVELOPER_DIR': '/Applications/Xcode.app', 'RUNNER_ARCH': 'X64',
                     'ImageOS': 'macos28', 'ImageVersion': '20261110.0001.1'}
        for key, value in mutations.items():
            with self.subTest(key=key):
                env = dict(ENV, **{key: value})
                run = MockRun()
                self.assertEqual(probe.execute(self.root, run, env), 1)
                self.assertEqual(run.calls, [])

    def test_checkout_toolchain_and_host_drift_stop_before_simulator(self):
        for name, value in (('tested-sha', 'b' * 40), ('architecture', 'x86_64'),
                            ('host-version', '27.1'), ('host-build', '26B1'),
                            ('xcode-version', 'Xcode 27.2\nBuild version bad'),
                            ('sdk-version', '27.1'), ('swift-version', 'unknown')):
            with self.subTest(name=name):
                code, run, state = self.prepare({name: value})
                self.assertEqual(code, 1)
                self.assertFalse(any('simctl' in argv for _, argv, _, _ in run.calls))
                self.assertEqual(state['ownership'], 'none')

    def test_success_requires_exact_boot_and_cleanup_readbacks(self):
        code, run, state = self.prepare()
        self.assertEqual(code, 0)
        self.assertEqual(state['uuid'], UUID)
        self.assertEqual(state['ownership'], 'created')
        self.assertTrue(state['boot_readback_verified'])
        boot = [c for c in run.calls if c[0] in ('boot', 'bootstatus', 'devices-booted')]
        self.assertEqual([c[3]['absolute_deadline'] for c in boot], [400, 400, 400])
        self.assertEqual(boot[0][1], ['xcrun', 'simctl', 'boot', '--arch=arm64', UUID])
        self.assertEqual(boot[0][2], 20)
        self.assertEqual(boot[1][1], ['xcrun', 'simctl', 'bootstatus', UUID])
        clean = MockRun()
        self.assertEqual(probe.cleanup(self.root, clean, ENV), 0)
        self.assertEqual([c[0] for c in clean.calls], ['cleanup-before', 'shutdown', 'delete', 'cleanup-after'])
        self.assertEqual(probe.summary(self.root, ENV), 0)

    def test_prepared_device_must_be_shutdown_before_boot(self):
        code, run, _ = self.prepare({'devices-prepared': json.dumps(device_fixture('Booted'))})
        self.assertEqual(code, 1)
        self.assertEqual(run.calls[-1][0], 'devices-prepared')

    def test_post_boot_readback_cannot_launch_at_boot_deadline(self):
        class LateBoot(MockRun):
            def run(self, name, *args, **kwargs):
                value = super().run(name, *args, **kwargs)
                if name == 'bootstatus':
                    self.now = 400
                return value
        run = LateBoot()
        self.assertEqual(probe.execute(self.root, run, ENV), 1)
        self.assertEqual(run.commands[-1]['name'], 'devices-booted')
        self.assertEqual(run.commands[-1]['status'], 'not_started')
        self.assertFalse(run.commands[-1]['launch_authorized'])

    def test_missing_middle_final_or_stale_manifest_prevents_cleanup(self):
        for name in ('run-11-preboot-disk-space.json', 'run-20-devices-booted.json', 'run-manifest.json',
                     'collect-manifest.json'):
            self.prepare()
            (self.root / name).unlink()
            clean = MockRun()
            self.assertEqual(probe.cleanup(self.root, clean, ENV), 1)
            self.assertEqual(clean.calls, [])
        self.prepare()
        manifest = probe.read(self.root / 'run-manifest.json')
        manifest['identity']['GITHUB_RUN_ID'] = 'wrong'
        write(self.root / 'run-manifest.json', manifest)
        clean = MockRun()
        self.assertEqual(probe.cleanup(self.root, clean, ENV), 1)
        self.assertEqual(clean.calls, [])

    def test_ready_summary_requires_complete_successful_command_inventory(self):
        self.prepare()
        self.assertEqual(probe.cleanup(self.root, MockRun(), ENV), 0)
        self.assertEqual(probe.summary(self.root, ENV), 0)
        (self.root / 'run-20-devices-booted.json').unlink()
        manifest = probe.read(self.root / 'run-manifest.json')
        manifest['commands'].pop()
        write(self.root / 'run-manifest.json', manifest)
        self.assertEqual(probe.summary(self.root, ENV), 1)

    def test_bootstatus_zero_is_not_readiness_without_booted_readback(self):
        code, _, state = self.prepare({'devices-booted': json.dumps(device_fixture('Shutdown'))})
        self.assertEqual(code, 1)
        self.assertNotEqual(state['status'], 'ready')
        self.assertNotIn('boot_readback_verified', state)

    def test_failure_stops_first_protected_command_without_retry(self):
        for name in ('runtimes', 'devices-before', 'create', 'devices-prepared', 'boot', 'bootstatus', 'devices-booted'):
            with self.subTest(name=name):
                code, run, _ = self.prepare({name: CommandFailure('timeout, partial output retained')})
                self.assertEqual(code, 1)
                self.assertEqual(run.calls[-1][0], name)
                self.assertEqual(sum(c[0] == name for c in run.calls), 1)

    def test_preboot_sampling_unavailable_fails_closed(self):
        code, run, state = self.prepare({'preboot-memory': CommandFailure('unavailable')})
        self.assertEqual(code, 1)
        self.assertEqual(state['sampling_unavailable'], 'preboot-memory')
        self.assertEqual(run.calls[-1][0], 'preboot-memory')

    def test_uncertain_create_or_malformed_uuid_never_authorizes_cleanup(self):
        for value in (CommandFailure('timeout'), 'invalid-uuid', UUID.lower().replace('1', 'a', 1)):
            code, _, state = self.prepare({'create': value})
            self.assertEqual(code, 1)
            self.assertEqual(state['ownership'], 'uncertain')
            clean = MockRun()
            self.assertEqual(probe.cleanup(self.root, clean, ENV), 1)
            self.assertEqual(clean.calls, [])

    def test_returned_preexisting_uuid_and_name_collision_fail_closed(self):
        fixture = device_fixture()
        for same_name in (True, False):
            changed = copy.deepcopy(fixture)
            if not same_name:
                changed['devices'][probe.RUNTIME][0]['name'] = 'Other device'
            code, _, state = self.prepare({'devices-before': json.dumps(changed)})
            self.assertEqual(code, 1)
            clean = MockRun()
            self.assertNotEqual(state.get('ownership'), 'created')
            probe.cleanup(self.root, clean, ENV)
            self.assertEqual(clean.calls, [])

    def test_cleanup_requires_current_identity_and_positive_ownership(self):
        for mutation in ({'identity': {}}, {'ownership': 'uncertain'}, {'uuid': OTHER},
                         {'preexisting_ids': [UUID]}, {'runtime': 'wrong'}, {'name': 'Other'}):
            self.prepare()
            state = probe.read(self.root / 'probe.json')
            state.update(mutation)
            write(self.root / 'probe.json', state)
            clean = MockRun()
            self.assertEqual(probe.cleanup(self.root, clean, ENV), 1)
            self.assertFalse(any(c[0] in ('shutdown', 'delete') for c in clean.calls))

    def test_cleanup_never_mutates_after_uncertain_or_wrong_readback(self):
        for before in (CommandFailure('timeout'), '{}', json.dumps({'devices': {}}),
                       json.dumps(device_fixture('Unknown'))):
            self.prepare()
            clean = MockRun({'cleanup-before': before})
            self.assertEqual(probe.cleanup(self.root, clean, ENV), 1)
            self.assertEqual([c[0] for c in clean.calls], ['cleanup-before'])

    def test_missing_or_uncertain_prior_command_blocks_cleanup(self):
        for record in ({}, {'status': 'timed_out', 'reaped': False, 'group_absent': None},
                       {'status': 'failure', 'reaped': True, 'group_absent': False}):
            self.prepare()
            write(self.root / 'run-01-tested-sha.json', record)
            clean = MockRun()
            self.assertEqual(probe.cleanup(self.root, clean, ENV), 1)
            self.assertEqual(clean.calls, [])
        self.prepare()
        (self.root / 'run-01-tested-sha.json').unlink()
        self.assertEqual(probe.cleanup(self.root, MockRun(), ENV), 1)

    def test_malformed_runtime_and_device_inventory_fail_closed(self):
        for value in (None, [], {}, {'runtimes': [None]}, {'runtimes': 'wrong'}):
            with self.assertRaises(ValueError):
                probe.runtime(value)
        for value in (None, [], {}, {'devices': {'runtime': None}}, {'devices': {'runtime': [None]}}):
            with self.assertRaises(ValueError):
                probe.devices(value)

    def test_cleanup_delete_requires_shutdown_success_and_absence_readback(self):
        for failed in ('shutdown', 'delete', 'cleanup-after'):
            self.prepare()
            clean = MockRun({failed: CommandFailure('timeout')})
            self.assertEqual(probe.cleanup(self.root, clean, ENV), 1)
            self.assertEqual(clean.calls[-1][0], failed)
        self.prepare()
        self.assertEqual(probe.cleanup(self.root, MockRun({'cleanup-after': json.dumps(device_fixture())}), ENV), 1)
        self.assertEqual(probe.summary(self.root, ENV), 1)

    def test_summary_tolerates_missing_malformed_and_nonobject_metadata(self):
        for content in ('{', '[]', 'null', '"bad"', '[' * 2000 + ']' * 2000):
            for name in ('probe.json', 'cleanup.json', 'collection.json'):
                (self.root / name).write_text(content)
            self.assertEqual(probe.summary(self.root, ENV), 1)
        for path in self.root.iterdir():
            path.unlink()
        self.assertEqual(probe.summary(self.root, ENV), 1)

    def test_readiness_and_diagnostic_completeness_are_reported_separately(self):
        self.prepare()
        probe.cleanup(self.root, MockRun(), ENV)
        with patch('builtins.print') as output:
            self.assertEqual(probe.summary(self.root, ENV), 0)
        text = output.call_args[0][0]
        self.assertIn('Readiness: ready', text)
        self.assertIn('Diagnostic capture: incomplete', text)
        self.assertIn('Unavailable: host-service-samples', text)
        self.assertIn('Readiness is not a root-cause finding.', text)
        self.assertEqual(probe.read(self.root / 'summary.json')['diagnostic_status'], 'incomplete')

    def test_missing_failed_upload_cannot_be_ready(self):
        self.prepare()
        probe.cleanup(self.root, MockRun(), ENV)
        for key in ('PROBE_OUTCOME', 'CLEANUP_OUTCOME', 'ARTIFACT_OUTCOME'):
            self.assertEqual(probe.summary(self.root, dict(ENV, **{key: 'failure'})), 1)

    def test_collector_caps_and_verifies_exact_service_identities(self):
        run = MockRun({'service-pids': '42\n43',
                       'service-identities': '42 /usr/libexec/mobileassetd\n43 /usr/libexec/cryptexd',
                       'sample-identity-42': '42 /usr/libexec/mobileassetd',
                       'sample-identity-43': '43 /wrong/other'})
        self.assertEqual(probe.collect(self.root, run, ENV), 0)
        names = [c[0] for c in run.calls]
        self.assertIn('sample-42', names)
        self.assertNotIn('sample-43', names)
        log = next(c for c in run.calls if c[0] == 'host-service-logs')
        self.assertIn('process == "mobileassetd"', log[1][-1])
        self.assertIn('process == "simdiskimaged"', log[1][-1])
        self.assertIn('process == "SimLaunchHost.arm64"', log[1][-1])
        lookup = next(c for c in run.calls if c[0] == 'service-pids')
        self.assertEqual(lookup[1][:2], ['pgrep', '-f'])
        self.assertTrue(all(c[3]['evidence'] for c in run.calls))
        for raw, identities in (('42', '42 /tmp/mobileassetd'), ('x', ''), ('\n'.join(str(i) for i in range(1, 18)), '')):
            bad = MockRun({'service-pids': raw, 'service-identities': identities})
            probe.collect(self.root, bad, ENV)
            self.assertFalse(any(c[0].startswith('sample-') for c in bad.calls))

    def test_collection_unavailable_is_labelled_without_invented_sample(self):
        run = MockRun({'service-pids': CommandFailure('permission denied'),
                       'post-mounts': CommandFailure('timeout')})
        probe.collect(self.root, run, ENV)
        result = probe.read(self.root / 'collection.json')
        self.assertEqual(result['sampled_pids'], [])
        self.assertTrue(result['unavailable'])

    def test_workflow_is_one_dispatch_only_job_with_immutable_actions(self):
        root = Path(__file__).resolve().parents[1]
        text = (root / '.github/workflows/ios.yml').read_text()
        triggers = text.split('on:', 1)[1].split('permissions:', 1)[0]
        self.assertEqual(re.findall(r'^  ([a-z_]+):', triggers, re.M), ['workflow_dispatch'])
        jobs = text.split('jobs:', 1)[1]
        self.assertEqual(re.findall(r'^  ([a-z-]+):', jobs, re.M), ['readiness-probe'])
        for value in ('github.run_attempt == 1', probe.REF, 'timeout-minutes: 25',
                      'retention-days: 30', 'EXPECTED_SOURCE_SHA: ${{ inputs.expected_source_sha }}',
                      'persist-credentials: false', 'runs-on: xcode-27'):
            self.assertIn(value, text)
        for forbidden in ('actions/cache', 'CI Gate\n', 'test-app.sh', 'prepare-app.sh', 'run-stage.py', 'matrix:', 'continue-on-error:'):
            self.assertNotIn(forbidden, text)
        self.assertLess(text.index('ci/readiness_probe.py collect'), text.index('ci/readiness_probe.py cleanup'))
        self.assertEqual(re.findall(r'uses: (\S+)', text), [
            'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1',
            'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a'])
        self.assertEqual(probe.BASE_SHA, 'aaac3dfe7e5c3b3804b5088578dc33bcef58cb17')
        self.assertEqual((probe.RUNTIME, probe.VERSION, probe.BUILD, probe.DEVELOPER_DIR),
                         ('com.apple.CoreSimulator.SimRuntime.iOS-27-2', '27.2', '24B8117',
                          '/Applications/Xcode_27.2.app/Contents/Developer'))
        self.assertEqual((probe.IMAGE_OS, probe.IMAGE_VERSION, probe.HOST_VERSION, probe.HOST_BUILD),
                         ('macos27', '20261104.0337.1', '27.0.1', '26A434'))


if __name__ == '__main__':
    unittest.main()

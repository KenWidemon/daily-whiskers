"""Dispatch-only, app-free readiness experiment; never CI acceptance evidence."""
import argparse
import json
import os
from pathlib import Path
import re
import sys
import time
import uuid

from probe_supervisor import CommandFailure, Supervisor, write

BASE_SHA = 'aaac3dfe7e5c3b3804b5088578dc33bcef58cb17'
REF = 'refs/heads/codex/ci-readiness-probe-20261111'
DEVELOPER_DIR = '/Applications/Xcode_27.2.app/Contents/Developer'
RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-27-2'
VERSION = '27.2'
BUILD = '24B8117'
IMAGE_OS = 'macos27'
IMAGE_VERSION = '20261104.0337.1'
HOST_VERSION = '27.0.1'
HOST_BUILD = '26A434'
DEVICE_TYPE = 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro'
SERVICES = ('com.apple.CoreSimulator.CoreSimulatorService', 'CoreSimulatorService',
            'mobileassetd', 'cryptexd', 'simdiskimaged', 'SimLaunchHost', 'SimLaunchHost.arm64')
RUN_COMMANDS = ('tested-sha', 'architecture', 'host-version', 'host-build', 'xcode-version',
                'sdk-version', 'swift-version', 'preboot-cpu-disk', 'preboot-memory',
                'preboot-swap', 'preboot-disk-space', 'preboot-mounts', 'preboot-runtime-images',
                'runtimes', 'devices-before', 'create', 'devices-prepared', 'boot',
                'bootstatus', 'devices-booted')
LIMITATION = ('App-free readiness only. Not full CI acceptance, cold/warm validation, '
              'or proof of timeout containment. Host descheduling, blocked system calls, '
              'detached services and abrupt runner loss remain outside the watchdog guarantee.')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def identity(env=os.environ):
    keys = ('GITHUB_SHA', 'EXPECTED_SOURCE_SHA', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT',
            'GITHUB_REF', 'GITHUB_REPOSITORY', 'GITHUB_JOB', 'GITHUB_EVENT_NAME')
    result = {key: env.get(key) for key in keys}
    require(re.fullmatch('[0-9a-f]{40}', result['EXPECTED_SOURCE_SHA'] or ''), 'Expected SHA must be immutable')
    require(result['GITHUB_SHA'] == result['EXPECTED_SOURCE_SHA'], 'Dispatch source mismatch')
    require(result['GITHUB_REF'] == REF and result['GITHUB_RUN_ATTEMPT'] == '1', 'Wrong branch or rerun')
    require(result['GITHUB_REPOSITORY'] == 'KenWidemon/daily-whiskers'
            and result['GITHUB_JOB'] == 'readiness-probe'
            and result['GITHUB_EVENT_NAME'] == 'workflow_dispatch', 'Wrong dispatch identity')
    require(re.fullmatch('[0-9]+', result['GITHUB_RUN_ID'] or ''), 'Missing run identity')
    require(env.get('DEVELOPER_DIR') == DEVELOPER_DIR and env.get('RUNNER_ARCH') == 'ARM64', 'Wrong runner/toolchain selection')
    require(env.get('ImageOS') == IMAGE_OS and env.get('ImageVersion') == IMAGE_VERSION,
            'Changed-condition blocker: hosted image differs from the diagnostic baseline')
    return result


def read(path):
    try:
        require(path.stat().st_size <= 1024 * 1024, 'Oversized metadata')
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {'status': 'unavailable', 'error': 'Metadata is not an object'}
    except (OSError, ValueError, TypeError, RecursionError) as error:
        return {'status': 'unavailable', 'error': type(error).__name__}


def valid_uuid(value):
    require(isinstance(value, str) and str(uuid.UUID(value)).upper() == value, 'Invalid UUID')
    return value


def runtime(data):
    require(isinstance(data, dict) and isinstance(data.get('runtimes'), list)
            and all(isinstance(r, dict) for r in data['runtimes']), 'Invalid runtime inventory')
    matches = [r for r in data['runtimes'] if r.get('identifier') == RUNTIME]
    require(len(matches) == 1, 'Missing or ambiguous exact runtime identifier')
    value = matches[0]
    require(value.get('version') == VERSION and value.get('buildversion') == BUILD
            and value.get('platform') == 'iOS' and value.get('isAvailable') is True,
            'Wrong or unavailable runtime build')
    require(isinstance(value.get('supportedArchitectures'), list)
            and 'arm64' in value['supportedArchitectures'], 'Runtime lacks arm64')
    require(isinstance(value.get('supportedDeviceTypes'), list)
            and all(isinstance(t, dict) for t in value['supportedDeviceTypes'])
            and any(t.get('identifier') == DEVICE_TYPE for t in value['supportedDeviceTypes']),
            'Runtime does not explicitly support iPhone 17 Pro')
    return value


def devices(data):
    require(isinstance(data, dict) and isinstance(data.get('devices'), dict)
            and all(isinstance(values, list) and all(isinstance(d, dict) for d in values)
                    for values in data['devices'].values()), 'Invalid device snapshot')
    return [(r, d) for r, values in data['devices'].items() for d in values]


def exact_device(data, state):
    matches = [(r, d) for r, d in devices(data) if d.get('udid') == state['uuid']]
    require(len(matches) == 1, 'Missing or ambiguous owned device')
    r, d = matches[0]
    require(r == RUNTIME and d.get('name') == state['name']
            and d.get('deviceTypeIdentifier') == DEVICE_TYPE and d.get('isAvailable') is True,
            'Owned destination identity differs')
    return d


def sim(run, name, *argv, timeout=10, absolute_deadline=None):
    return run.run(name, ['xcrun', 'simctl', *argv], timeout, absolute_deadline=absolute_deadline)


def snapshot(run, name, kind='devices', timeout=10, absolute_deadline=None):
    return json.loads(sim(run, name, 'list', kind, '--json', timeout=timeout,
                          absolute_deadline=absolute_deadline))


def execute(directory, run, env=os.environ):
    state = {'status': 'running', 'ownership': 'none', 'uuid': None, 'base_sha': BASE_SHA,
             'runtime': RUNTIME, 'version': VERSION, 'build': BUILD,
             'device_type': DEVICE_TYPE, 'wall_start': time.time(), 'limitation': LIMITATION}
    state['runner_image'] = {key: env.get(key, 'unavailable') for key in ('ImageOS', 'ImageVersion')}
    state['observed_context'] = {key: env.get(key, 'unavailable') for key in
                                 ('GITHUB_SHA', 'EXPECTED_SOURCE_SHA', 'GITHUB_RUN_ID',
                                  'GITHUB_RUN_ATTEMPT', 'GITHUB_REF')}
    path = directory / 'probe.json'
    write(path, state)
    try:
        state['identity'] = identity(env)
        state['name'] = f"DW-readiness-{env['GITHUB_RUN_ID']}-1"
        write(path, state)
        tested = run.run('tested-sha', ['git', 'rev-parse', 'HEAD'])
        state['tested_sha'] = tested
        require(tested == state['identity']['EXPECTED_SOURCE_SHA'], 'Checkout differs from expected SHA')
        require(run.run('architecture', ['uname', '-m']) == 'arm64', 'Wrong architecture')
        require(run.run('host-version', ['sw_vers', '-productVersion']) == HOST_VERSION, 'Changed host OS version')
        require(run.run('host-build', ['sw_vers', '-buildVersion']) == HOST_BUILD, 'Changed host OS build')
        require(run.run('xcode-version', ['xcodebuild', '-version']).splitlines() == ['Xcode 27.2', 'Build version 27B52'], 'Wrong Xcode build')
        require(run.run('sdk-version', ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version']) == '27.2', 'Wrong simulator SDK')
        require('Apple Swift version' in run.run('swift-version', ['xcrun', 'swift', '--version']), 'Missing Swift identity')
        state['toolchain_verified'] = True
        state['toolchain'] = {'developer_dir': DEVELOPER_DIR, 'architecture': 'arm64',
                              'xcode': '27.2', 'xcode_build': '27B52', 'sdk': '27.2',
                              'host_version': HOST_VERSION, 'host_build': HOST_BUILD}
        write(path, state)
        # Fixed, one-shot host samples only; no process arguments or environments.
        for name, argv in (
                ('preboot-cpu-disk', ['iostat', '-c', '1']),
                ('preboot-memory', ['vm_stat']),
                ('preboot-swap', ['sysctl', '-n', 'vm.swapusage']),
                ('preboot-disk-space', ['df', '-k', '/']),
                ('preboot-mounts', ['mount']),
                ('preboot-runtime-images', ['xcrun', 'simctl', 'runtime', 'list', '--json'])):
            try:
                run.run(name, argv)
            except CommandFailure:
                state['sampling_unavailable'] = name
                raise
        runtime(snapshot(run, 'runtimes', 'runtimes'))
        before = snapshot(run, 'devices-before', timeout=20)
        state['preexisting_ids'] = [valid_uuid(d['udid']) for _, d in devices(before)]
        require(not any(d.get('name') == state['name'] for _, d in devices(before)), 'Run-owned name already exists')
        state.update(status='creating', ownership='uncertain')
        write(path, state)
        identifier = valid_uuid(sim(run, 'create', 'create', state['name'], DEVICE_TYPE, RUNTIME, timeout=20))
        require(identifier not in state['preexisting_ids'], 'Create returned a preexisting UUID')
        state.update(uuid=identifier, ownership='created')
        write(path, state)
        require(exact_device(snapshot(run, 'devices-prepared', timeout=20), state).get('state')
                == 'Shutdown', 'Prepared owned device is not Shutdown')
        # Both boot commands share one original 300-second maximum.
        boot_deadline = min(run.deadline, run.clock() + 300)
        sim(run, 'boot', 'boot', '--arch=arm64', identifier, timeout=20, absolute_deadline=boot_deadline)
        remaining = boot_deadline - run.clock()
        require(remaining > 0, 'Boot budget exhausted before bootstatus')
        sim(run, 'bootstatus', 'bootstatus', identifier, timeout=300, absolute_deadline=boot_deadline)
        require(exact_device(snapshot(run, 'devices-booted', absolute_deadline=boot_deadline), state).get('state') == 'Booted', 'Exact boot readback failed')
        state.update(status='ready', boot_readback_verified=True)
    except (CommandFailure, OSError, ValueError, KeyError, TypeError) as error:
        state.update(status='failure', error=f'{type(error).__name__}: {error}')
    save_manifest(directory, 'run', run, state.get('identity'))
    state['wall_end'] = time.time()
    write(path, state)
    return 0 if state['status'] == 'ready' else 1


def save_manifest(directory, phase, run, current):
    # Written only after the controller returns from every attempted command.
    # Abrupt loss leaves this terminal manifest missing, never implicitly complete.
    write(directory / f'{phase}-manifest.json', {
        'identity': current, 'phase': phase, 'terminal': True,
        'commands': [f'{phase}-{index:02d}-{record["name"]}.json'
                     for index, record in enumerate(run.commands, 1)]})


def verified_command_records(directory, phase, current, *, successful_names=None):
    manifest = read(directory / f'{phase}-manifest.json')
    require(manifest.get('terminal') is True and manifest.get('identity') == current
            and manifest.get('phase') == phase, 'Missing, stale or interrupted phase manifest')
    expected = manifest.get('commands')
    require(isinstance(expected, list) and 0 < len(expected) <= 32
            and all(isinstance(name, str) and re.fullmatch(phase + r'-[0-9]{2}-[a-z0-9-]+\.json', name)
                    for name in expected), 'Invalid phase command manifest')
    paths = sorted(directory.glob(f'{phase}-[0-9][0-9]-*.json'))
    require([path.name for path in paths] == expected, 'Missing, extra or reordered command records')
    names = []
    for index, path in enumerate(paths, 1):
        record = read(path)
        name = record.get('name')
        require(path.name == f'{phase}-{index:02d}-{name}.json', 'Command identity differs from manifest')
        names.append(name)
        if record.get('status') == 'not_started' and record.get('pid') is None and successful_names is None:
            continue
        require(isinstance(record.get('pid'), int) and record['pid'] > 0
                and record.get('reaped') is True and record.get('group_absent') is True,
                'Command containment/reaping uncertain; no cleanup mutation permitted')
        if successful_names is not None:
            require(record.get('status') == 'success' and record.get('exit_code') == 0
                    and record.get('launch_authorized') is True
                    and record.get('exec_attempt_observed') is True
                    and record.get('pgid') == record['pid']
                    and record.get('output_truncated') is False, 'Incomplete successful command evidence')
    if successful_names is not None:
        require(tuple(names) in successful_names, 'Successful command inventory is incomplete')
    return True


def cleanup(directory, run, env=os.environ):
    result = {'status': 'running', 'readback_verified': False, 'operation': 'none'}
    try:
        current = identity(env)
        state = read(directory / 'probe.json')
        require(state.get('identity') == current, 'Stale or missing ownership identity')
        result.update(identity=current, uuid=state.get('uuid'), ownership=state.get('ownership'))
        require(state.get('ownership') in ('none', 'created'), 'Uncertain creation; no mutation permitted')
        if state['ownership'] == 'none':
            require(state.get('uuid') is None, 'Unexpected UUID without ownership')
            result.update(status='success', operation='not-created', readback_verified=True)
        else:
            verified_command_records(directory, 'run', current)
            verified_command_records(directory, 'collect', current)
            identifier = valid_uuid(state['uuid'])
            require(identifier not in state['preexisting_ids'], 'Refusing preexisting UUID')
            require(state.get('name') == f"DW-readiness-{current['GITHUB_RUN_ID']}-1"
                    and state.get('runtime') == RUNTIME and state.get('build') == BUILD
                    and state.get('version') == VERSION and state.get('device_type') == DEVICE_TYPE,
                    'Ownership contract changed')
            device = exact_device(snapshot(run, 'cleanup-before', timeout=20), state)
            result['operation'] = 'delete-owned'
            write(directory / 'cleanup.json', result)
            require(device.get('state') in ('Booted', 'Shutdown'), 'Uncertain device state; no mutation permitted')
            if device.get('state') != 'Shutdown':
                sim(run, 'shutdown', 'shutdown', identifier, timeout=20)
            sim(run, 'delete', 'delete', identifier, timeout=20)
            after = snapshot(run, 'cleanup-after', timeout=20)
            require(not any(d.get('udid') == identifier for _, d in devices(after)), 'Owned UUID persists after deletion')
            result.update(status='success', readback_verified=True)
    except (CommandFailure, OSError, ValueError, KeyError, TypeError) as error:
        result.update(status='failure', error=f'{type(error).__name__}: {error}')
    save_manifest(directory, 'cleanup', run, result.get('identity'))
    write(directory / 'cleanup.json', result)
    return 0 if result['status'] == 'success' else 1


def collect(directory, run, env=os.environ):
    result = {'status': 'complete', 'unavailable': [], 'sampled_pids': []}
    def capture(name, argv):
        try:
            return run.run(name, argv, evidence=True)
        except CommandFailure as error:
            result['unavailable'].append({'name': name, 'error': str(error)})
            return None
    current = None
    try:
        current = identity(env)
        # Fixed exact service names retain historical logs even if a service
        # crashed or restarted. PID-based sampling still needs live validation.
        predicate = ' OR '.join(f'process == "{name}"' for name in SERVICES)
        capture('host-service-logs', ['log', 'show', '--last', '15m', '--style', 'compact', '--predicate', predicate])
        capture('post-mounts', ['mount'])
        capture('post-memory', ['vm_stat'])
        capture('post-swap', ['sysctl', '-n', 'vm.swapusage'])
        raw = capture('service-pids', ['pgrep', '-f', r'(^|/)(' + '|'.join(re.escape(n) for n in SERVICES) + r')( |$)'])
        pids = raw.splitlines() if raw else []
        require(len(pids) <= 16 and all(re.fullmatch('[1-9][0-9]*', p) for p in pids), 'Invalid or excessive service PID inventory')
        verified = []
        if pids:
            rows = capture('service-identities', ['ps', '-p', ','.join(pids), '-o', 'pid=,comm='])
            for line in (rows or '').splitlines():
                pid, executable = line.strip().split(None, 1)
                require(pid in pids and Path(executable).name in SERVICES, 'Unverified host service identity')
                require(executable.startswith(('/System/Library/', '/usr/libexec/', '/Library/Developer/', DEVELOPER_DIR + '/')), 'Unexpected host service executable')
                verified.append((pid, executable))
            result['verified_services'] = verified
        if verified:
            for pid, _ in verified[:2]:
                identity_now = capture('sample-identity-' + pid, ['ps', '-p', pid, '-o', 'pid=,comm='])
                if not identity_now or identity_now.strip().split(None, 1) != [pid, _]:
                    result['unavailable'].append({'name': 'sample-' + pid, 'error': 'Service identity changed or unavailable'})
                    continue
                if capture('sample-' + pid, ['sample', pid, '1', '20', '-file', '/dev/stdout']) is not None:
                    result['sampled_pids'].append(pid)
        else:
            result['unavailable'].append({'name': 'host-service-samples', 'error': 'No exact verified service PIDs'})
    except (ValueError, OSError, TypeError) as error:
        result['unavailable'].append({'name': 'collection', 'error': str(error)})
    save_manifest(directory, 'collect', run, current)
    write(directory / 'collection.json', result)
    return 0


def summary(directory, env=os.environ):
    probe, clean, collection = [read(directory / name) for name in ('probe.json', 'cleanup.json', 'collection.json')]
    try:
        current = identity(env)
        valid_uuid(probe.get('uuid'))
        verified_command_records(directory, 'run', current, successful_names=(RUN_COMMANDS,))
        verified_command_records(directory, 'collect', current)
        verified_command_records(directory, 'cleanup', current, successful_names=(
            ('cleanup-before', 'shutdown', 'delete', 'cleanup-after'),
            ('cleanup-before', 'delete', 'cleanup-after')))
        require((probe.get('runtime'), probe.get('version'), probe.get('build'), probe.get('device_type'))
                == (RUNTIME, VERSION, BUILD, DEVICE_TYPE), 'Readiness destination differs')
        passed = (all(env.get(key) == 'success' for key in ('PROBE_OUTCOME', 'CLEANUP_OUTCOME', 'ARTIFACT_OUTCOME'))
                  and probe.get('identity') == clean.get('identity') == current
                  and probe.get('tested_sha') == current['EXPECTED_SOURCE_SHA']
                  and probe.get('status') == 'ready' and probe.get('toolchain_verified') is True
                  and probe.get('boot_readback_verified') is True
                  and clean.get('status') == 'success' and clean.get('readback_verified') is True
                  and clean.get('operation') == 'delete-owned' and clean.get('uuid') == probe.get('uuid'))
    except (ValueError, TypeError, AttributeError):
        passed = False
    unavailable = collection.get('unavailable')
    if not isinstance(unavailable, list):
        unavailable = [{'name': 'collection', 'error': 'Missing or malformed diagnostic metadata'}]
    diagnostic_status = 'complete' if collection.get('status') == 'complete' and not unavailable else 'incomplete'
    result = {'status': 'ready' if passed else 'failed-or-inconclusive',
              'diagnostic_status': diagnostic_status, 'probe': probe,
              'cleanup': clean, 'collection': collection, 'artifact_url': env.get('ARTIFACT_URL', 'unavailable'), 'limitation': LIMITATION}
    write(directory / 'summary.json', result)
    content = ('## App-free readiness probe\n\nReadiness: ' + result['status']
               + '\nCleanup: ' + str(clean.get('status', 'unavailable'))
               + '\nDiagnostic capture: ' + diagnostic_status + '\n\n'
               + 'Readiness is not a root-cause finding.\n\n')
    for item in unavailable[:32]:
        if not isinstance(item, dict):
            item = {'name': 'diagnostic metadata', 'error': 'Malformed unavailable entry'}
        content += f'- Unavailable: {str(item.get("name", "unknown"))[:100]}: {str(item.get("error", "unknown"))[:500]}\n'
    content += '\n'
    for key in ('identity', 'observed_context', 'tested_sha', 'runtime', 'version', 'build', 'uuid', 'runner_image', 'toolchain', 'error'):
        content += f'- {key}: {json.dumps(probe.get(key, "unavailable"))}\n'
    content += f'\nCleanup: {json.dumps(clean)}\n\n{LIMITATION}\n'
    destination = env.get('GITHUB_STEP_SUMMARY')
    if destination:
        with open(destination, 'a') as output:
            output.write(content)
    print(content)
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('phase', choices=('run', 'cleanup', 'collect', 'summary'))
    args = parser.parse_args()
    directory = Path(os.environ['RUNNER_TEMP']) / 'dw-readiness-probe'
    directory.mkdir(parents=True, exist_ok=True)
    if args.phase == 'summary':
        return summary(directory)
    seconds, shutdown = {'run': (600, 65), 'cleanup': (45, 15), 'collect': (75, 15)}[args.phase]
    require(not (directory / f'{args.phase}-budget.json').exists(), 'Phase may execute only once')
    with Supervisor(directory, args.phase, seconds, shutdown) as run:
        return {'run': execute, 'cleanup': cleanup, 'collect': collect}[args.phase](directory, run)


if __name__ == '__main__':
    sys.exit(main())

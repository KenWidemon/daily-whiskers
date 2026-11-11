"""Exact hosted destination selection and bounded, owned-only simulator cleanup.

Tests inject simctl; importing this module never inspects or changes simulators.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

NAME = 'iPhone 17 Pro'
DEVICE_TYPE = 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro'
RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'
VERSION = '27.0'
BUILD = '24A434'
DEVELOPER_DIR = '/Applications/Xcode_27.2.app/Contents/Developer'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def write(path, record):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(record, indent=2) + '\n')
    temporary.replace(path)


def identity():
    return {key: os.getenv(value) for key, value in {
        'source_sha': 'SOURCE_SHA', 'tested_sha': 'TESTED_SHA', 'run_id': 'GITHUB_RUN_ID',
        'run_attempt': 'GITHUB_RUN_ATTEMPT', 'job': 'GITHUB_JOB', 'shard': 'CI_SHARD_ID'}.items()}


def valid_uuid(value):
    require(isinstance(value, str) and str(uuid.UUID(value)).upper() == value, 'Invalid simulator UUID')
    return value


def verify_toolchain(text):
    lines = text.splitlines()
    for expected in (f'Developer directory: {DEVELOPER_DIR}', 'Architecture: arm64',
                     'Xcode 27.2', 'Build version 27B52', 'Simulator SDK: 27.2'):
        prefix = expected.split(':', 1)[0] + ':' if ':' in expected else ('Xcode ' if expected.startswith('Xcode ') else 'Build version ')
        require([line for line in lines if line.startswith(prefix)] == [expected], f'Unexpected toolchain: {expected}')
    require(any('Apple Swift version' in line for line in lines), 'Missing Swift version')


def exact_runtime(data):
    matches = [r for r in data['runtimes'] if r.get('identifier') == RUNTIME]
    require(len(matches) == 1, 'Missing/ambiguous exact iOS runtime')
    runtime = matches[0]
    require(runtime.get('platform') == 'iOS' and runtime.get('isAvailable') is True and runtime.get('version') == VERSION
            and runtime.get('buildversion') == BUILD, 'Unavailable or wrong runtime version/build')
    require(isinstance(runtime.get('supportedArchitectures'), list)
            and 'arm64' in runtime['supportedArchitectures'], 'Runtime lacks ARM64 support')
    types = runtime.get('supportedDeviceTypes', [])
    require(isinstance(types, list) and any(isinstance(d, dict) and d.get('identifier') == DEVICE_TYPE for d in types),
            'Runtime does not explicitly support iPhone 17 Pro')
    return runtime


def all_devices(data):
    return [(runtime, device) for runtime, devices in data['devices'].items() for device in devices]


def exact_device(data, identifier):
    matches = [(r, d) for r, d in all_devices(data) if d.get('udid') == identifier]
    require(len(matches) == 1, 'Missing/ambiguous simulator readback')
    runtime, device = matches[0]
    require(runtime == RUNTIME and device.get('name') == NAME
            and device.get('deviceTypeIdentifier') == DEVICE_TYPE and device.get('isAvailable') is True,
            'Simulator readback differs from exact destination')
    return device


class Simctl:
    def __init__(self, seconds):
        self.deadline = time.monotonic() + seconds

    def __call__(self, *args):
        remaining = self.deadline - time.monotonic()
        require(remaining > 0, 'Simulator operation deadline exhausted')
        return subprocess.check_output(['xcrun', 'simctl', *args], text=True,
                                       stderr=subprocess.PIPE, timeout=min(20, remaining)).strip()


def snapshot(simctl, directory, name, kind='devices'):
    raw = simctl('list', kind, '--json')
    (directory / f'simulator-{name}.json').write_text(raw + '\n')
    return json.loads(raw)


def prepare(directory, simctl):
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / 'simulator.json'
    require(not path.exists(), 'Simulator preparation must run only once')
    record = dict(identity(), status='preparing', ownership='none', runtime=RUNTIME,
                  version=VERSION, build=BUILD, architecture='arm64', device_type=DEVICE_TYPE,
                  name=NAME, simulator_id=None)
    write(path, record)
    try:
        exact_runtime(snapshot(simctl, directory, 'runtimes', 'runtimes'))
        before = snapshot(simctl, directory, 'devices-before')
        record['preexisting_ids'] = [valid_uuid(d['udid']) for _, d in all_devices(before)]
        candidates = [d for r, d in all_devices(before) if r == RUNTIME and d.get('name') == NAME
                      and d.get('deviceTypeIdentifier') == DEVICE_TYPE and d.get('isAvailable') is True]
        require(len(candidates) <= 1, 'Ambiguous preexisting exact simulator; refusing to choose')
        if candidates:
            record.update(ownership='preexisting', simulator_id=valid_uuid(candidates[0]['udid']))
        else:
            # Persist intent before creating. A killed/ambiguous create never
            # authorizes deletion by name or by a guessed difference from baseline.
            record.update(status='creating', ownership='uncertain')
            write(path, record)
            identifier = valid_uuid(simctl('create', NAME, DEVICE_TYPE, RUNTIME))
            require(identifier not in record['preexisting_ids'], 'Create returned a preexisting UUID')
            record.update(ownership='created', simulator_id=identifier)
        write(path, record)
        exact_device(snapshot(simctl, directory, 'devices-prepared'), record['simulator_id'])
        record.update(status='ready', readback_verified=True)
        write(path, record)
        with open(os.environ['GITHUB_ENV'], 'a') as output:
            output.write(f"SIMULATOR_ID={record['simulator_id']}\n")
        print(f"Simulator: {NAME} / iOS {VERSION} ({BUILD}) / {record['simulator_id']} / {record['ownership']}")
        return 0
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError) as error:
        record.update(status='failure', error=f'{type(error).__name__}: {error}')
        write(path, record)
        print(record['error'], file=sys.stderr)
        return 1


def cleanup(directory, simctl):
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / 'cleanup-status.json'
    started = time.monotonic()
    record = dict(identity(), stage='cleanup', status='running', operation='none', readback_verified=False)
    write(path, record)
    try:
        preparation = json.loads((directory / 'simulator.json').read_text())
        require(all(preparation.get(k) == v for k, v in identity().items()), 'Stale simulator ownership record')
        ownership, identifier = preparation['ownership'], preparation.get('simulator_id')
        record.update(ownership=ownership, simulator_id=identifier)
        require(ownership in ('created', 'preexisting', 'none'), 'Creation outcome/ownership uncertain; manual inspection required')
        if ownership == 'none':
            require(identifier is None, 'Unexpected simulator without ownership')
            record['operation'] = 'not-created'
        else:
            valid_uuid(identifier)
            before = snapshot(simctl, directory, 'devices-cleanup-before')
            if ownership == 'preexisting':
                exact_device(before, identifier)
                record['operation'] = 'preserved-preexisting'
            else:
                require(identifier not in preparation['preexisting_ids'], 'Refusing to delete a preexisting simulator')
                device = exact_device(before, identifier)
                record['operation'] = 'delete-owned'
                write(path, record)
                if device.get('state') != 'Shutdown':
                    simctl('shutdown', identifier)
                simctl('delete', identifier)
                after = snapshot(simctl, directory, 'devices-after')
                require(not any(d.get('udid') == identifier for _, d in all_devices(after)),
                        'Owned simulator still present after delete')
        record.update(status='success', exit_code=0, readback_verified=True)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError) as error:
        record.update(status='failure', exit_code=1, error=f'{type(error).__name__}: {error}')
        print(record['error'], file=sys.stderr)
    record['duration_seconds'] = round(time.monotonic() - started, 2)
    write(path, record)
    return record['exit_code']


def verify_evidence(preparation, cleanup_record, current, part):
    expected = dict(source_sha=current['SOURCE_SHA'], tested_sha=current['TESTED_SHA'],
                    run_id=current['GITHUB_RUN_ID'], run_attempt=current['GITHUB_RUN_ATTEMPT'],
                    job='build-and-test' if part == 'unit-release' else 'ui-shards', shard=part)
    require(all(preparation.get(k) == v for k, v in expected.items()), 'Stale simulator preparation evidence')
    for key, value in dict(status='ready', runtime=RUNTIME, version=VERSION, build=BUILD,
                           architecture='arm64', name=NAME, device_type=DEVICE_TYPE).items():
        require(preparation.get(key) == value, f'Invalid simulator preparation {key}')
    require(preparation.get('readback_verified') is True, 'Unverified simulator preparation')
    identifier = valid_uuid(preparation['simulator_id'])
    ownership = preparation['ownership']
    require(ownership in ('created', 'preexisting'), 'Unknown simulator ownership')
    require((identifier in preparation['preexisting_ids']) == (ownership == 'preexisting'), 'Inconsistent simulator provenance')
    require(cleanup_record.get('simulator_id') == identifier and cleanup_record.get('ownership') == ownership
            and cleanup_record.get('readback_verified') is True
            and cleanup_record.get('operation') == ('delete-owned' if ownership == 'created' else 'preserved-preexisting'),
            'Missing/uncertain simulator cleanup readback')
    return identifier


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=('prepare', 'cleanup', 'verify-toolchain'))
    parser.add_argument('--directory', type=Path, default=Path('build'))
    args = parser.parse_args()
    if args.command == 'verify-toolchain':
        verify_toolchain((args.directory / 'toolchain.txt').read_text())
    else:
        # Cleanup has one shared 45-second command deadline, within its one-minute
        # always step. No command retries; timeout/uncertainty remains a failure.
        sys.exit((prepare if args.command == 'prepare' else cleanup)(args.directory, Simctl(90 if args.command == 'prepare' else 45)))

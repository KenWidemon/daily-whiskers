"""Readiness only: never build, install, launch or test an app."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

import simulator as policy


OUT = Path('build/sim-readiness')
OWNERSHIP = OUT / 'ownership.json'
WALL_BUDGET = 360
POLL_INTERVAL = 30
STATES = {'Creating', 'Shutdown', 'Booting', 'Booted', 'Shutting Down', 'Deleting'}
PHASES = ('Waiting on BackBoard', 'Waiting on Data Migration', 'Waiting on System App', 'Finished')
STATUS = re.compile(r'Status=(\d+), isTerminal=(YES|NO), Elapsed=(\d+:\d+(?::\d+)?)')


def command(args, seconds):
    return subprocess.run(args, text=True, capture_output=True, check=True, timeout=seconds).stdout.strip()


def simctl(*args, seconds=15):
    return command(['xcrun', 'simctl', *args], seconds)


def devices(seconds=15):
    data = json.loads(simctl('list', 'devices', '--json', seconds=seconds))
    return policy.all_devices(data)


def fingerprint(device_rows, excluded=None):
    ids = sorted(policy.valid_uuid(item['udid']) for _, item in device_rows if item['udid'] != excluded)
    return {'count': len(ids), 'sha256': hashlib.sha256('\n'.join(ids).encode()).hexdigest()}


def state(rows, ownership):
    matches = [(runtime, item) for runtime, item in rows if item['udid'] == ownership['uuid']]
    if not matches:
        return 'absent'
    policy.require(len(matches) == 1, 'Ambiguous owned UUID')
    runtime, item = matches[0]
    policy.require(runtime == policy.RUNTIME and item['deviceTypeIdentifier'] == policy.DEVICE_TYPE
                   and item['name'] == ownership['name'], 'Owned UUID identity mismatch')
    value = item['state']
    policy.require(value in STATES, 'Unrecognized simulator state')
    return value


def elapsed(started):
    return round(time.monotonic() - started, 3)


def owned_record():
    record = json.loads(OWNERSHIP.read_text())
    policy.require(record['identity'] == policy.identity(), 'Stale ownership record')
    if record['status'] == 'created':
        policy.valid_uuid(record['uuid'])
        policy.require(record['uuid_was_absent_from_baseline'] is True, 'No proof of new UUID')
    elif record['status'] != 'none':
        raise ValueError('Simulator creation outcome uncertain; no mutation authorized')
    return record


def readiness():
    OUT.mkdir(parents=True, exist_ok=False)
    started = time.monotonic()
    record = dict(identity=policy.identity(), status='none', uuid=None)
    evidence = dict(identity=record['identity'], status='started', timeline=[])
    policy.write(OWNERSHIP, record)
    try:
        developer = os.environ.get('DEVELOPER_DIR')
        arch = command(['uname', '-m'], 5)
        version = command(['xcodebuild', '-version'], 15)
        sdk = command(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], 15)
        policy.require((developer, arch, version, sdk) == (policy.DEVELOPER_DIR, 'arm64',
                       'Xcode 27.2\nBuild version 27B52', '27.2'), 'Pinned toolchain mismatch')
        evidence['toolchain'] = dict(directory=developer, architecture=arch, xcode=version, sdk=sdk,
                                     runner_image=os.getenv('ImageOS'), runner_revision=os.getenv('ImageVersion'))
        policy.exact_runtime(json.loads(simctl('list', 'runtimes', '--json')))
        baseline = devices()
        name = f"DW143 Ready {os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}"
        policy.require(not any(item['name'] == name for _, item in baseline), 'Name already exists')
        record.update(status='creating', name=name, baseline=fingerprint(baseline))
        policy.write(OWNERSHIP, record)
        identifier = policy.valid_uuid(simctl('create', name, policy.DEVICE_TYPE, policy.RUNTIME, seconds=25))
        policy.require(all(item['udid'] != identifier for _, item in baseline), 'UUID was already present')
        record.update(status='created', uuid=identifier, uuid_was_absent_from_baseline=True)
        policy.write(OWNERSHIP, record)
        policy.require(state(devices(), record) == 'Shutdown', 'Fresh simulator not in Shutdown state')
        evidence['timeline'].append(dict(phase='created', readiness_elapsed_seconds=elapsed(started)))
        simctl('boot', identifier, seconds=45)
        evidence['timeline'].append(dict(phase='boot-returned', readiness_elapsed_seconds=elapsed(started)))
        policy.write(OUT / 'readiness.json', evidence)
        boot_started = time.monotonic()
        next_poll = boot_started
        raw = OUT.parent / 'sim-readiness-bootstatus-private.log'
        try:
            with raw.open('wb') as output:
                monitor = subprocess.Popen(['xcrun', 'simctl', 'bootstatus', identifier, '-b'],
                                           stdout=output, stderr=subprocess.STDOUT)
                try:
                    while monitor.poll() is None and elapsed(boot_started) < WALL_BUDGET:
                        if time.monotonic() >= next_poll:
                            sampled_at = elapsed(boot_started)
                            try:
                                seen = state(devices(seconds=min(8, max(0.1, WALL_BUDGET - sampled_at))), record)
                                sample = dict(state=seen)
                            except (subprocess.SubprocessError, json.JSONDecodeError, OSError, KeyError, TypeError) as error:
                                sample = dict(sample_error_type=type(error).__name__)
                            evidence['timeline'].append(dict(phase='state-sample', boot_elapsed_seconds=sampled_at, **sample))
                            policy.write(OUT / 'readiness.json', evidence)
                            next_poll = time.monotonic() + POLL_INTERVAL
                        time.sleep(min(1, max(0, WALL_BUDGET - elapsed(boot_started))))
                    evidence['bootstatus_exit'] = monitor.poll()
                    evidence['bootstatus_timed_out'] = monitor.poll() is None
                finally:
                    if monitor.poll() is None:
                        monitor.terminate()
                        try:
                            monitor.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            monitor.kill()
                            monitor.wait(timeout=5)
            with raw.open('rb') as stream:
                sample = stream.read(131072).decode(errors='replace')
            unique = dict.fromkeys(STATUS.findall(sample))
            evidence['bootstatus_signals'] = [dict(status=s, terminal=t, elapsed=e) for s, t, e in unique]
            evidence['bootstatus_known_phases'] = [phase for phase in PHASES if phase in sample]
        finally:
            evidence['boot_observed_seconds'] = elapsed(boot_started)
            if raw.exists():
                raw.unlink()
            try:
                evidence['terminal_state'] = state(devices(), record)
            except (OSError, ValueError, subprocess.SubprocessError, KeyError, TypeError) as error:
                evidence['terminal_state_error_type'] = type(error).__name__
        policy.require(evidence.get('bootstatus_exit') == 0, 'Boot readiness not achieved within bounded observation')
        policy.require(evidence['terminal_state'] == 'Booted', 'Ready state lacked independent Booted readback')
        evidence['status'] = 'ready'
        return 0
    except (OSError, ValueError, subprocess.SubprocessError, KeyError, TypeError) as error:
        evidence.update(status='not-ready-or-inconclusive', error_type=type(error).__name__)
        print(f'Readiness failed: {error}', file=sys.stderr)
        return 1
    finally:
        evidence['total_seconds'] = elapsed(started)
        policy.write(OUT / 'readiness.json', evidence)


def verify(cleanup):
    started = time.monotonic()
    evidence = dict(identity=policy.identity(), status='started')
    try:
        record = owned_record()
        if record['status'] == 'none':
            evidence['status'] = 'not-created'
            return 0
        rows = devices()
        evidence['observed_state'] = state(rows, record)
        if cleanup and evidence['observed_state'] != 'absent':
            if evidence['observed_state'] != 'Shutdown':
                try:
                    simctl('shutdown', record['uuid'], seconds=45)
                except subprocess.SubprocessError as error:
                    evidence['shutdown_error_type'] = type(error).__name__
            current = state(devices(), record)
            evidence['before_delete'] = current
            if current == 'Shutdown':
                simctl('delete', record['uuid'], seconds=25)
            elif current != 'absent':
                raise ValueError('Owned simulator shutdown not verified; no delete attempted')
            rows = devices()
        evidence['final_state'] = state(rows, record)
        evidence['baseline_inventory_matches'] = fingerprint(rows) == record['baseline']
        policy.require(evidence['final_state'] == 'absent', 'Owned simulator absence not verified')
        policy.require(evidence['baseline_inventory_matches'], 'Baseline device inventory changed')
        evidence['status'] = 'absent-verified'
        return 0
    except (OSError, ValueError, subprocess.SubprocessError, KeyError, TypeError) as error:
        evidence.update(status='unverified', error_type=type(error).__name__)
        print(f'Cleanup/absence check failed: {error}', file=sys.stderr)
        return 1
    finally:
        evidence['elapsed_seconds'] = elapsed(started)
        policy.write(OUT / ('cleanup.json' if cleanup else 'absence.json'), evidence)


if __name__ == '__main__':
    action, = sys.argv[1:]
    assert action in ('readiness', 'cleanup', 'verify-absence')
    sys.exit(readiness() if action == 'readiness' else verify(action == 'cleanup'))

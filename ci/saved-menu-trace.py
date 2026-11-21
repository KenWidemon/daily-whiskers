"""One diagnostic method on the already validated and exclusively owned simulator."""
import json
import os
import plistlib
import pty
import re
import select
import signal
import subprocess
import sys
import time
from pathlib import Path

import simulator as policy

SELECTOR = 'DailyWhiskersUITests/SavedCardsTests/testSaveRelaunchReopenShareRemoveAndConfirmedClear'
SCOPED_TEST_ID = 'SavedCardsTests/testSaveRelaunchReopenShareRemoveAndConfirmedClear()'
SUBSYSTEM = 'com.example.kenwidemon.dailywhiskers'
PREDICATE = f'subsystem == "{SUBSYSTEM}" AND category == "saved-menu-trace"'
BUILD = Path('build').resolve()
EVIDENCE = BUILD / 'trace-evidence'


def exact_test_case(node):
    if isinstance(node, dict):
        if node.get('nodeType') == 'Test Case':
            yield (node.get('nodeIdentifier'), node.get('nodeIdentifierURL', ''))
        for value in node.values():
            yield from exact_test_case(value)
    elif isinstance(node, list):
        for value in node:
            yield from exact_test_case(value)


def owned_simulator():
    record = json.loads((BUILD / 'simulator.json').read_text())
    policy.require(all(record.get(k) == v for k, v in policy.identity().items()), 'Stale simulator ownership')
    policy.require(record.get('ownership') == 'created', 'Simulator creation not proven; do not mutate')
    identifier = policy.valid_uuid(record['simulator_id'])
    policy.require(identifier not in record['preexisting_ids'], 'Cannot operate on a baseline simulator')
    return identifier, record


def inventory(seconds=20):
    return json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json'],
                                              text=True, timeout=seconds))


def independent_state(identifier, attempts=2):
    errors = []
    for _ in range(attempts):
        try:
            return policy.exact_device(inventory(), identifier)['state'], errors
        except subprocess.TimeoutExpired as error:
            errors.append(type(error).__name__)
    return None, errors


def boot_after_build(identifier, evidence, save):
    state, errors = independent_state(identifier)
    evidence.update(post_build_state=state, post_build_inventory_timeouts=errors)
    save()
    policy.require(state in ('Shutdown', 'Booted'), 'Owned simulator state not established after build')
    if state == 'Shutdown':
        subprocess.run(['xcrun', 'simctl', 'boot', identifier], check=True, timeout=45)
    started = time.monotonic()
    result = None
    raw = b''
    try:
        # No inventory, log stream or other simctl observer while bootstatus runs.
        completed = subprocess.run(['xcrun', 'simctl', 'bootstatus', identifier, '-b'],
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=360)
        result, raw = completed.returncode, completed.stdout
    except subprocess.TimeoutExpired as error:
        raw = error.stdout or b''
        evidence['bootstatus_timed_out'] = True
    finally:
        evidence['bootstatus_exit'] = result
        evidence['bootstatus_elapsed_seconds'] = round(time.monotonic() - started, 3)
        evidence['bootstatus_signals'] = re.findall(
            r'Status=(\d+), isTerminal=(YES|NO), Elapsed=(\d+:\d+(?::\d+)?)',
            raw[:131072].decode(errors='replace'))[:400]
        save()
    state, errors = independent_state(identifier)
    evidence.update(post_watch_state=state, post_watch_inventory_timeouts=errors)
    save()
    policy.require(result == 0 and state == 'Booted', 'Observer and inventory did not both establish readiness')


def cleanup(verify_only):
    name = 'absence-status.json' if verify_only else 'cleanup-status.json'
    evidence = dict(policy.identity(), status='started', phase='ownership')
    try:
        identifier, record = owned_simulator()
        evidence['simulator_id'] = identifier
        before = inventory()
        present = any(d['udid'] == identifier for _, d in policy.all_devices(before))
        if present:
            evidence['initial_state'] = policy.exact_device(before, identifier)['state']
            if not verify_only:
                evidence['phase'] = 'shutdown'
                if evidence['initial_state'] != 'Shutdown':
                    try:
                        subprocess.run(['xcrun', 'simctl', 'shutdown', identifier], check=True, timeout=45)
                    except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
                        evidence['shutdown_error_type'] = type(error).__name__
                evidence['phase'] = 'pre-delete-read'
                after_shutdown = inventory()
                still_present = any(d['udid'] == identifier for _, d in policy.all_devices(after_shutdown))
                if still_present:
                    policy.require(policy.exact_device(after_shutdown, identifier)['state'] == 'Shutdown',
                                   'Owned shutdown was not verified; refuse to delete')
                    evidence['phase'] = 'delete'
                    subprocess.run(['xcrun', 'simctl', 'delete', identifier], check=True, timeout=25)
        evidence['phase'] = 'final-inventory'
        final = before if verify_only else inventory()
        ids = {policy.valid_uuid(d['udid']) for _, d in policy.all_devices(final)}
        evidence['owned_absent'] = identifier not in ids
        evidence['baseline_matches'] = ids == set(record['preexisting_ids'])
        policy.require(evidence['owned_absent'] and evidence['baseline_matches'], 'Owned absence or baseline verification failed')
        evidence['status'] = 'absent-verified'
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        evidence.update(status='unverified', error_type=type(error).__name__)
        print(f'Owned simulator cleanup/readback failed: {error}', file=sys.stderr)
        return 1
    finally:
        policy.write(BUILD / name, evidence)


def run():
    EVIDENCE.mkdir(parents=True, exist_ok=False)
    readiness = dict(identity=policy.identity(), status='starting', bootstatus_timed_out=False)
    save = lambda: policy.write(EVIDENCE / 'readiness.json', readiness)
    save()
    simulator, ownership = owned_simulator()
    policy.require(simulator == os.environ['SIMULATOR_ID'] and ownership.get('readback_verified') is True,
                   'Destination is not a newly owned verified simulator')
    state, errors = independent_state(simulator)
    readiness.update(simulator=simulator, initial_state=state, initial_inventory_timeouts=errors)
    save()
    policy.require(state == 'Shutdown', 'Build-first requires a fresh owned Shutdown simulator')
    destination = f'platform=iOS Simulator,id={simulator},arch=arm64'
    derived = BUILD / 'TraceDerivedData'
    traced_run = BUILD / 'Trace.xcresult'
    readiness['status'] = 'building-first'
    build_started = time.monotonic()
    save()
    subprocess.run(['xcodebuild', 'build-for-testing', '-project', 'DailyWhiskers.xcodeproj',
                    '-scheme', 'DailyWhiskersInteraction', '-configuration', 'Debug',
                    '-destination', destination, '-derivedDataPath', str(derived),
                    '-clonedSourcePackagesDirPath', str(BUILD / 'SourcePackages'),
                    '-onlyUsePackageVersionsFromResolvedFile', '-disableAutomaticPackageResolution',
                    'CODE_SIGNING_ALLOWED=NO', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING',
                    '-parallel-testing-enabled', 'NO'], check=True)
    readiness.update(status='build-succeeded', build_elapsed_seconds=round(time.monotonic() - build_started, 3))
    save()
    lock = Path('DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
    if lock.read_bytes() != (Path(os.environ['RUNNER_TEMP']) / 'Package.resolved.expected').read_bytes():
        raise ValueError('Dependency lock changed during build')
    original, = (derived / 'Build/Products').glob('*.xctestrun')
    config = plistlib.loads(original.read_bytes())
    if set(config) != {'DailyWhiskersUITests', '__xctestrun_metadata__'}:
        raise ValueError('Unexpected test target or xctestrun schema')
    target = config['DailyWhiskersUITests']
    if 'DailyWhiskersUITests' not in target.get('TestBundlePath', ''):
        raise ValueError('Unexpected UI test bundle')
    optin = target.setdefault('EnvironmentVariables', {})
    if 'DW_SAVED_MENU_TRACE' in optin:
        raise ValueError('Unexpected pre-existing trace flag')
    optin['DW_SAVED_MENU_TRACE'] = '1'
    runner = original.with_name('DW143Trace.xctestrun')
    runner.write_bytes(plistlib.dumps(config))
    if plistlib.loads(runner.read_bytes()) != config:
        raise ValueError('Trace launch configuration did not round-trip')
    cmd = ['xcodebuild', 'test-without-building', '-xctestrun', str(runner), '-destination', destination,
           '-parallel-testing-enabled', 'NO', '-test-timeouts-enabled', 'YES',
           '-default-test-execution-time-allowance', '720', '-maximum-test-execution-time-allowance', '720',
           '-resultBundlePath', str(traced_run), f'-only-testing:{SELECTOR}']
    readiness['status'] = 'observing-readiness-after-build'
    save()
    try:
        boot_after_build(simulator, readiness, save)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        readiness.update(status='not-ready-or-inconclusive', error_type=type(error).__name__)
        save()
        raise
    readiness['status'] = 'observer-and-inventory-ready'
    save()
    receipt = dict(selector=SELECTOR, collector_ready=False, attempted=False, exit_code=None,
                   simulator=simulator, source_sha=os.environ['SOURCE_SHA'],
                   tested_sha=os.environ['TESTED_SHA'], run_id=os.environ['GITHUB_RUN_ID'],
                   run_attempt=os.environ['GITHUB_RUN_ATTEMPT'])

    def save():
        (EVIDENCE / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

    save()
    master, slave = pty.openpty()
    collector = None
    test = None
    capture = bytearray()
    try:
        # Inherit the outer stage's process group so its deadline also stops the collector.
        collector = subprocess.Popen(['xcrun', 'simctl', 'spawn', simulator, 'log', 'stream',
                                      '--style', 'compact', '--level', 'debug', '--timeout', '15m',
                                      '--predicate', PREDICATE], stdin=subprocess.DEVNULL,
                                     stdout=slave, stderr=slave)
        os.close(slave)
        slave = None

        def read_once():
            if select.select([master], [], [], 0.25)[0]:
                try:
                    capture.extend(os.read(master, 65536))
                except OSError:
                    pass  # PTY EOF; exit status below disambiguates capture.
            if len(capture) > 128 * 1024:
                raise ValueError('Scoped trace exceeded the evidence cap')

        deadline = time.monotonic() + 15
        while time.monotonic() < deadline and collector.poll() is None:
            read_once()
            if b'Filtering the log data' in capture and b'saved-menu-trace' in capture:
                break
        if collector.poll() is not None or b'Filtering the log data' not in capture or b'saved-menu-trace' not in capture:
            raise ValueError('Scoped collector did not report ready; method not attempted')
        receipt['collector_ready'] = True
        save()
        with (BUILD / 'trace-test.log').open('wb') as log:
            test = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
            receipt.update(attempted=True, xcodebuild_pid=test.pid, spawned_at_utc_epoch=time.time())
            save()
            while test.poll() is None:
                read_once()
            receipt['exit_code'] = test.returncode
        for _ in range(6):
            read_once()
        receipt['collector_alive_through_drain'] = collector.poll() is None
    finally:
        if test is not None and test.poll() is None:
            test.terminate()
            try:
                test.wait(timeout=10)
            except subprocess.TimeoutExpired:
                test.kill()
                test.wait(timeout=5)
        if collector is not None and collector.poll() is None:
            collector.send_signal(signal.SIGINT)
            try:
                collector.wait(timeout=5)
            except subprocess.TimeoutExpired:
                collector.terminate()
                try:
                    collector.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    collector.kill()
                    collector.wait(timeout=5)
        if slave is not None:
            os.close(slave)
        os.close(master)
        lines = capture.decode(errors='replace').splitlines()
        markers = [line for line in lines if f'[{SUBSYSTEM}:saved-menu-trace] saved-menu/' in line]
        (EVIDENCE / 'markers.txt').write_text('\n'.join(markers) + '\n')
        receipt['probe_enabled_observed'] = any(line.endswith('saved-menu/probe-enabled') for line in markers)
        receipt['drop_notice_observed'] = any('dropped' in line.lower() for line in lines)
        save()
    for section in ('summary', 'tests', 'activities'):
        call = ['xcrun', 'xcresulttool', 'get', 'test-results', section, '--path', str(traced_run)]
        if section == 'activities':
            call += ['--test-id', SCOPED_TEST_ID]
        result = subprocess.run(call, capture_output=True, timeout=60)
        if result.returncode == 0 and len(result.stdout) <= 1024 * 1024:
            data = json.loads(result.stdout)
            if section == 'activities':
                selected = []

                def collect(node):
                    if isinstance(node, dict):
                        title = node.get('title', '')
                        if any(key in title for key in ('ActivityListView', '[0.05, 0.25]', '[0.05, 0.70]',
                                                       'Saved card system share', '05 Saved Card Options',
                                                       'saved-card-toggle" Button to not exist', 'Final test state',
                                                       'Removed detail remains readable')):
                            selected.append({key: node[key] for key in ('title', 'startTime', 'finishTime')
                                             if key in node})
                        for value in node.values():
                            collect(value)
                    elif isinstance(node, list):
                        for value in node:
                            collect(value)

                collect(data)
                data = selected
            (EVIDENCE / f'{section}.json').write_text(json.dumps(data, indent=2) + '\n')
    summary = EVIDENCE / 'summary.json'
    tested = EVIDENCE / 'tests.json'
    activities = EVIDENCE / 'activities.json'
    collected = (receipt['collector_alive_through_drain'] and receipt['probe_enabled_observed']
                 and not receipt['drop_notice_observed'] and summary.exists() and tested.exists()
                 and activities.exists())
    if collected:
        summary_data = json.loads(summary.read_text())
        cases = list(exact_test_case(json.loads(tested.read_text())))
        devices = summary_data.get('devicesAndConfigurations', [])
        expected_device = dict(architecture='arm64', deviceId=simulator, modelName='iPhone 17 Pro',
                               osBuildNumber='24A434', osVersion='27.0', platform='iOS Simulator')
        collected = (summary_data.get('totalTestCount') == 1 and len(cases) == 1
                     and cases[0][0] == SCOPED_TEST_ID and cases[0][1].endswith('/' + SELECTOR)
                     and len(devices) == 1 and all(devices[0].get('device', {}).get(k) == v
                                                   for k, v in expected_device.items()))
    receipt['collection_complete'] = collected
    anchored = False
    if collected:
        rows = sorted(json.loads(activities.read_text()), key=lambda row: row.get('startTime', 0))
        anchors = ('Added attachment named "04 Saved card system share"',
                   '[0.05, 0.25]', 'Added attachment named "05 Saved Card Options"',
                   '[0.05, 0.70]', 'saved-card-toggle" Button to not exist')
        next_anchor = 0
        for row in rows:
            if next_anchor == len(anchors):
                break
            if row.get('startTime') and anchors[next_anchor] in row['title'].replace("'", '"'):
                next_anchor += 1
        anchored = next_anchor == len(anchors)
    receipt['comparison_window_observed'] = anchored
    receipt['share_completion_marker_observed'] = any(line.endswith('saved-menu/share-anchor-complete') for line in markers)
    receipt['enabled_after_share_marker_observed'] = any('saved-menu/enabled-item-applied-after-share/' in line for line in markers)
    receipt['focus_post_marker_observed'] = any(line.endswith('saved-menu/options-focus-layout-posted') for line in markers)
    marker_checklist = all(receipt[key] for key in ('share_completion_marker_observed',
                                                   'enabled_after_share_marker_observed',
                                                   'focus_post_marker_observed'))
    receipt['diagnostic_capture_complete'] = anchored and marker_checklist
    save()
    return receipt['exit_code'] or (0 if receipt['diagnostic_capture_complete'] else 2)


if __name__ == '__main__':
    args = sys.argv[1:]
    if not args:
        sys.exit(run())
    if args in (['cleanup'], ['verify-absence']):
        sys.exit(cleanup(args == ['verify-absence']))
    sys.exit(2)

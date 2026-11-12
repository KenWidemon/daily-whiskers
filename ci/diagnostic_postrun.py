"""Post-run owned-container evidence. No live polling, process discovery or sampling."""
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import time

import diagnostic as d

MARKER_STREAMS = {'cards': 'cards', 'startup': 'startup', 'reminder': 'reminder_ui'}
MAX_MARKER_BYTES = 2 * 1024 * 1024
MAX_TRACE_BYTES = 4 * 1024 * 1024


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def exported_container(bundle, until):
    """Read the owned device's exact MCM identity even after xcodebuild shuts it down.

    No boot, inventory polling, guessed container, or fallback to another device.
    The fixed local device set must agree with the preparation snapshot and plist.
    """
    identifier = d.owned()['simulator_id']
    prepared = json.loads((d.BUILD / 'simulator-devices-prepared.json').read_text())
    device = d.simulator.exact_device(prepared, identifier)
    root = Path.home() / 'Library/Developer/CoreSimulator/Devices' / identifier
    data = root / 'data'
    d.require(root.resolve(strict=True) == root and data.resolve(strict=True) == data
              and Path(device['dataPath']) == data, 'Foreign/symlinked owned-device data path')
    def plist(path):
        d.require(time.time() < until and path.stat().st_size <= 65536
                  and path.resolve(strict=True) == path, 'Container metadata bound/path exceeded')
        return plistlib.loads(path.read_bytes())
    info = plist(root / 'device.plist')
    d.require(all(info.get(k) == v for k, v in {'UDID': identifier, 'name': d.simulator.NAME,
              'runtime': d.simulator.RUNTIME, 'deviceType': d.simulator.DEVICE_TYPE, 'isDeleted': False}.items()),
              'Owned-device metadata mismatch')
    folder = data / 'Containers/Data/Application'
    d.require(folder.resolve(strict=True) == folder, 'Foreign container directory')
    matches = []
    for index, item in enumerate(folder.iterdir()):
        d.require(index < 512 and time.time() < until, 'Container scan bound exceeded')
        d.simulator.valid_uuid(item.name)
        d.require(item.is_dir() and item.resolve(strict=True) == item, 'Foreign/symlinked container')
        meta = item / '.com.apple.mobile_container_manager.metadata.plist'
        value = plist(meta)
        if value.get('MCMMetadataIdentifier') == bundle['bundle_id']:
            matches.append((item, meta))
    d.require(len(matches) == 1, 'Missing/ambiguous exact bundle container metadata')
    return matches[0]


def read_markers(path):
    d.require(path.stat().st_size <= MAX_MARKER_BYTES, 'Marker stream exceeds fixed bound')
    raw = path.read_bytes()
    # An in-flight final line is retained, not parsed as a complete marker.
    complete = raw.endswith(b'\n')
    lines = raw.splitlines() if complete else raw.splitlines()[:-1]
    return [json.loads(line) for line in lines], complete


def valid_marker(row, runner_pid, metadata, stage):
    d.require(row.get('schema_version') == 1 and row.get('pid') == runner_pid
              and row.get('runner_bundle_id') == metadata['bundles']['runner']['bundle_id'], 'Foreign marker identity')
    selector = dict(d.LANES[metadata['lane']])[stage]
    d.require(normalize_test_name(row.get('test', ''), selector)
              and row.get('stream') == MARKER_STREAMS.get(stage, 'cards'),
              'Wrong selected-test marker')
    d.require(row.get('record_complete') is True and row.get('dropped_event_count') == 0
              and row.get('fields_truncated') is False and not row.get('export_error'), 'Incomplete/overflowed marker stream')
    for key in ('event_wall_time', 'export_wall_time'):
        d.require(isinstance(row.get(key), (int, float)), 'Missing marker clock')


def normalize_test_name(name, selector):
    target, case, method = selector.split('/')
    # XCTestCase.name is an Objective-C style name, not a slash selector.
    match = re.fullmatch(r'-\[(?:(\w+)\.)?(\w+) (test\w+)\]', name)
    return bool(match and match[1] in (None, target) and match[2] == case and match[3] == method)


def export_all(checkpoint=None, until=None):
    """Evidence reserve operation: a single 35s deadline, before owned cleanup."""
    until = until or time.time() + 35
    output = dict(d.identity(), status='running', files=[], containers=[], errors=[], started=time.time())
    path = d.DIAGNOSTIC / (f'{checkpoint}-export.json' if checkpoint else 'export.json')
    d.write(path, output)
    try:
        metadata = json.loads((d.DIAGNOSTIC / 'built-metadata.json').read_text())
        d.require(all(metadata.get(k) == v for k, v in d.identity().items()), 'Stale built metadata')
        if metadata['lane'] == 'visual':
            output.update(status='complete', finished=time.time(), scope='No UI marker/trace export required')
            d.write(path, output)
            return 0
        from diagnostic_results import validate_launch
        launched = []
        for stage, _ in d.LANES[metadata['lane']]:
            launch_path = d.DIAGNOSTIC / stage / 'launch.json'
            if launch_path.exists():
                launch = json.loads(launch_path.read_text())
                validate_launch(launch, stage, d.identity(), d.budget()['deadline'])
                launched.append(stage)
        output['launched_stages'] = launched
        d.require(launched, 'No selected method launched; containers/markers unavailable')
        for kind, bundle in metadata['bundles'].items():
            try:
                data, meta = exported_container(bundle, until)
                receipt = (d.DIAGNOSTIC / checkpoint if checkpoint else d.DIAGNOSTIC) / f'{kind}-container-metadata.plist'
                shutil.copyfile(meta, receipt)
                output['containers'].append({'kind': kind, 'bundle_id': bundle['bundle_id'],
                                             'path': str(data), 'metadata': str(receipt),
                                             'method': 'exact-owned-device MCM metadata'})
                sources = ((data / 'Documents/ci-diagnostic', ('*.jsonl', '*.error.json'), MAX_MARKER_BYTES)
                           if kind == 'runner' else (data / 'Library/Caches/DailyWhiskersCIDiagnostics', ('reminder-*.json',), MAX_TRACE_BYTES))
                folder, patterns, limit = sources
                destination = (d.DIAGNOSTIC / checkpoint if checkpoint else d.DIAGNOSTIC) / 'exported' / kind
                destination.mkdir(parents=True, exist_ok=True)
                files = [source for pattern in patterns for source in folder.glob(pattern)]
                d.require(len(files) <= 32, 'Unexpected diagnostic export file count')
                for source in files:
                    d.require(time.time() < until and source.stat().st_size <= limit, 'Diagnostic export bound exceeded')
                    d.require(folder.resolve() == folder and source.resolve() == source, 'Unexpected export symlink')
                    shutil.copyfile(source, destination / source.name)
                    output['files'].append({'kind': kind, 'source': str(source), 'path': str(destination / source.name),
                                            'bytes': source.stat().st_size, 'sha256': digest(destination / source.name), 'copied_wall_time': time.time()})
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                output['errors'].append(f'{kind}: {type(error).__name__}: {error}')
    except (OSError, ValueError, KeyError, TypeError) as error:
        output['errors'].append(str(error))
    output.update(status='inconclusive' if output['errors'] else 'complete', finished=time.time())
    d.write(path, output)
    return 1 if output['errors'] else 0


def installed_bundles(metadata, until):
    """Bind exported identities to this build, including the UI test executable."""
    identifier = d.owned()['simulator_id']
    root = Path.home() / 'Library/Developer/CoreSimulator/Devices' / identifier / 'data/Containers/Bundle/Application'
    d.require(root.resolve(strict=True) == root, 'Symlinked installed bundle root')
    matches = {kind: [] for kind in metadata['bundles']}
    for index, folder in enumerate(root.iterdir()):
        d.require(index < 512 and time.time() < until, 'Installed bundle scan bound exceeded')
        d.require(folder.resolve(strict=True) == folder and folder.is_dir(), 'Foreign bundle folder')
        for app in folder.glob('*.app'):
            info_path = app / 'Info.plist'
            d.require(app.resolve(strict=True) == app and info_path.resolve(strict=True) == info_path
                      and info_path.stat().st_size <= 65536, 'Invalid installed bundle metadata')
            info = plistlib.loads(info_path.read_bytes())
            for kind, built in metadata['bundles'].items():
                if info.get('CFBundleIdentifier') == built['bundle_id']:
                    d.require(info.get('CFBundleExecutable') == built['executable'], 'Wrong installed executable')
                    d.require(built['binaries'] and built['executable'] in built['binaries'], 'Missing build hashes')
                    for relative, expected in built['binaries'].items():
                        file = app / relative
                        original = Path(built['built_path']) / relative
                        d.require(time.time() < until and file.resolve(strict=True) == file
                                  and digest(file) == digest(original) == expected, 'Installed/build binary mismatch')
                    matches[kind].append({'path': str(app), 'bundle_id': built['bundle_id'],
                                          'binaries': built['binaries']})
    d.require(all(len(items) == 1 for items in matches.values()), 'Missing/ambiguous installed build')
    return {kind: items[0] for kind, items in matches.items()}


MARKER_CLOCK_DOMAIN = 'darwin.CLOCK_UPTIME_RAW'


def marker_uptime_ns():
    """Swift DispatchTime uptime domain, unlike older Python's process epoch.

    Only evidence timestamps use this clock. The same-process watchdog duration
    clock is unchanged. Never silently fall back to time.monotonic_ns().
    """
    d.require(sys.platform == 'darwin' and hasattr(time, 'CLOCK_UPTIME_RAW')
              and callable(getattr(time, 'clock_gettime_ns', None)), 'Shared Darwin uptime clock unavailable')
    stamp = time.clock_gettime_ns(time.CLOCK_UPTIME_RAW)
    d.require(type(stamp) is int and stamp > 0, 'Invalid shared Darwin uptime clock')
    return stamp


def execute(command, lane, stage):
    metadata = json.loads((d.DIAGNOSTIC / 'built-metadata.json').read_text())
    d.require(all(metadata.get(k) == v for k, v in d.identity().items()), 'Stale built metadata')
    until = d.deadline()
    directory = d.DIAGNOSTIC / stage
    directory.mkdir(parents=True, exist_ok=True)
    started, monotonic = time.time(), marker_uptime_ns()
    process = subprocess.Popen(command)  # Inherits run-stage's owned watchdog group.
    launch = dict(d.identity(), stage=stage, pid=process.pid, parent_pid=os.getpid(),
                  process_group=os.getpgrp(), command=command, started=started,
                  started_monotonic_ns=monotonic, monotonic_clock_domain=MARKER_CLOCK_DOMAIN,
                  deadline=until, evidence_mode='post-run-only')
    d.write(directory / 'launch.json', launch)
    # No polling, simctl lookup, ps discovery, sampling, or shorter startup cutoff.
    code = process.wait()
    d.write(directory / 'exit.json', dict(d.identity(), stage=stage, launch=launch,
            exit_code=code, finished=time.time(), finished_monotonic_ns=marker_uptime_ns(),
            monotonic_clock_domain=MARKER_CLOCK_DOMAIN))
    return code


def finite_clock(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def validate_invocation(launch, exit_record, stage):
    from diagnostic_results import validate_launch
    validate_launch(launch, stage, d.identity(), d.budget()['deadline'])
    d.require(launch.get('monotonic_clock_domain') == exit_record.get('monotonic_clock_domain') == MARKER_CLOCK_DOMAIN,
              'Missing/foreign cross-process clock domain')
    d.require(launch.get('evidence_mode') == 'post-run-only' and exit_record.get('launch') == launch
              and exit_record.get('stage') == stage
              and all(exit_record.get(k) == v for k, v in d.identity().items()), 'Foreign post-run invocation')
    d.require(finite_clock(launch['started']) and finite_clock(exit_record['finished'])
              and launch['started'] <= exit_record['finished'] <= launch['deadline'], 'Invalid invocation wall clock')
    d.require(type(launch['started_monotonic_ns']) is int and type(exit_record['finished_monotonic_ns']) is int
              and 0 < launch['started_monotonic_ns'] <= exit_record['finished_monotonic_ns'], 'Invalid invocation monotonic clock')


def validate_stream(path, stage, launch, exit_record, container_path, metadata):
    from diagnostic_results import validate_markers
    rows, complete = read_markers(path)
    d.require(rows and complete, 'Empty/partial marker stream')
    first = rows[0]
    pid = first.get('pid')
    d.require(type(pid) is int and pid > 0, 'Invalid post-run marker PID')
    d.require(path.name == f"{MARKER_STREAMS.get(stage, 'cards')}-{pid}-{first['session_id']}.jsonl",
              'Marker filename does not match stream/PID/session')
    for row in rows:
        d.require(row.get('process_name') == metadata['bundles']['runner']['executable'], 'Wrong runner executable')
        for key in ('event_wall_time', 'export_wall_time'):
            d.require(finite_clock(row.get(key)) and launch['started'] <= row[key] <= exit_record['finished'],
                      'Stale/out-of-invocation marker wall clock')
        d.require(row['event_wall_time'] <= row['export_wall_time'], 'Marker export precedes event')
        for key in ('event_monotonic_ns', 'export_monotonic_ns'):
            value = row.get(key)
            d.require(isinstance(value, str) and re.fullmatch('[1-9][0-9]{0,19}', value) is not None
                      and launch['started_monotonic_ns'] <= int(value) <= exit_record['finished_monotonic_ns'],
                      'Stale/out-of-invocation marker monotonic clock')
    identity = {'stage': stage, 'runner_pid': pid, 'runner_data_container': container_path}
    result = validate_markers([path], dict(d.LANES[metadata['lane']])[stage], identity, metadata)
    return dict(result, sha256=digest(path), identity_basis='POST-RUN owned container + bounded invocation markers',
                runner_data_container=container_path, live_runner_observed=False)


def verify_evidence(stage, *, collect=False):
    """Verify a frozen per-invocation export before unlocking the next method."""
    current = d.identity()
    if current['lane'] == 'visual':
        return {'mode': 'post-run-only', 'scope': 'No UI marker/trace required'}
    directory = d.DIAGNOSTIC / stage
    path = directory / 'postrun.json'
    if not collect:
        until = min(d.deadline(), time.time() + 35)
        d.require(export_all(checkpoint=stage, until=until) == 0, 'Post-run export incomplete')
        metadata = json.loads((d.DIAGNOSTIC / 'built-metadata.json').read_text())
        report = dict(current, stage=stage, mode='post-run-only', live_diagnostics='not requested',
                      installed=installed_bundles(metadata, until))
        d.write(path, report)
    report = json.loads(path.read_text())
    metadata = json.loads((d.DIAGNOSTIC / 'built-metadata.json').read_text())
    d.require(all(report.get(k) == v and metadata.get(k) == v for k, v in current.items())
              and report.get('stage') == stage and report.get('mode') == 'post-run-only', 'Foreign post-run record')
    export = json.loads((d.DIAGNOSTIC / f'{stage}-export.json').read_text())
    d.require(all(export.get(k) == v for k, v in current.items()) and export.get('status') == 'complete'
              and not export.get('errors'), 'Incomplete/foreign stage export')
    containers = {row['kind']: row for row in export['containers']}
    d.require(len(containers) == len(export['containers']) == 2, 'Missing/duplicate owned containers')
    for kind, bundle in metadata['bundles'].items():
        receipt = containers[kind]
        d.require(receipt['bundle_id'] == report['installed'][kind]['bundle_id'] == bundle['bundle_id']
                  and report['installed'][kind]['binaries'] == bundle['binaries'], 'Export/build association mismatch')
        meta = plistlib.loads(Path(receipt['metadata']).read_bytes())
        d.require(meta.get('MCMMetadataIdentifier') == bundle['bundle_id'], 'Foreign retained MCM metadata')
    for item in export['files']:
        file = Path(item['path'])
        d.require(file.parent == directory / 'exported' / item['kind'] and file.name == Path(item['source']).name
                  and digest(file) == item['sha256'], 'Changed/foreign exported file')
    actual = list((directory / 'exported').glob('*/*'))
    d.require({str(p) for p in actual} == {f['path'] for f in export['files']}, 'Unrecorded/duplicate exported files')
    d.require(not list((directory / 'exported/runner').glob('*.error.json')), 'Marker export sidecar error')
    markers = {}
    for file in (directory / 'exported/runner').glob('*.jsonl'):
        rows, complete = read_markers(file)
        d.require(rows and complete, 'Empty/partial exported marker stream')
        matching = [name for name, selector in d.LANES[current['lane']]
                    if normalize_test_name(rows[0].get('test', ''), selector)]
        d.require(len(matching) == 1 and matching[0] in export['launched_stages'], 'Unattributed marker stream')
        name = matching[0]
        d.require(name not in markers, 'Ambiguous marker session')
        launch = json.loads((d.DIAGNOSTIC / name / 'launch.json').read_text())
        exited = json.loads((d.DIAGNOSTIC / name / 'exit.json').read_text())
        validate_invocation(launch, exited, name)
        markers[name] = validate_stream(file, name, launch, exited, containers['runner']['path'], metadata)
    d.require(set(markers) == set(export['launched_stages']) and stage in markers, 'Missing selected marker stream')
    report['marker_evidence'] = markers[stage]
    if stage == 'reminder':
        from diagnostic_results import validate_trace
        traces = list((directory / 'exported/app').glob('reminder-*.json'))
        d.require(len(traces) == 1, 'Missing/ambiguous reminder trace')
        trace = json.loads(traces[0].read_text())
        launch = json.loads((directory / 'launch.json').read_text())
        exited = json.loads((directory / 'exit.json').read_text())
        for event in trace['events']:
            d.require(launch['started'] <= event['wall_time_unix'] <= exited['finished']
                      and launch['started_monotonic_ns'] <= event['monotonic_ns'] <= exited['finished_monotonic_ns'],
                      'Trace belongs to another invocation')
        d.require(launch['started_monotonic_ns'] <= trace['capture_started_monotonic_ns']
                  <= trace['capture_complete_through_monotonic_ns'] <= exited['finished_monotonic_ns'],
                  'Trace capture outside invocation')
        report['reminder_trace'] = validate_trace(traces[0], d.BUILD / 'reminder.log')
        report['reminder_trace']['sha256'] = digest(traces[0])
        report['reminder_trace']['app_bundle_id'] = containers['app']['bundle_id']
    elif list((directory / 'exported/app').glob('reminder-*.json')):
        d.require(False, 'Unexpected reminder trace outside reminder invocation')
    report['status'] = 'complete'
    if not collect:
        d.write(path, report)
    return report

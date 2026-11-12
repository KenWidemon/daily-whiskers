"""Bounded, exact-PID diagnostic observation, never a system-wide sampler."""
import json
import os
import plistlib
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time

import diagnostic as d

MARKER_STREAMS = {'cards': 'cards', 'startup': 'startup', 'reminder': 'reminder_ui'}
MAX_MARKER_BYTES = 2 * 1024 * 1024
MAX_TRACE_BYTES = 4 * 1024 * 1024
MAX_HELPER_CALLS = 96  # Per invocation; at most two invocations in a lane.
_helper_calls = 0


def host_output(args, **kwargs):
    global _helper_calls
    d.require(_helper_calls < MAX_HELPER_CALLS, 'Host helper-call budget exhausted')
    _helper_calls += 1
    return d.run_output(args, **kwargs)


def container(bundle, kind, until):
    identifier = d.owned()['simulator_id']
    result = host_output(['xcrun', 'simctl', 'get_app_container', identifier,
                           bundle['bundle_id'], kind], seconds=3, until=until)
    path = Path(result).resolve(strict=True)
    # Never substitute a guessed container or another booted simulator.
    d.require(identifier in path.parts and 'Containers' in path.parts, 'Container is outside the owned simulator')
    d.require(path.is_dir(), 'Container is not a directory')
    return path


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


def process_row(pid, until):
    raw = host_output(['/bin/ps', '-ww', '-p', str(pid), '-o', 'pid=,ppid=,pgid=,%cpu=,rss=,comm='],
                       seconds=2, until=until)
    fields = raw.split(None, 5)
    d.require(len(fields) == 6 and int(fields[0]) == pid, 'Exact PID unavailable')
    return {'pid': pid, 'ppid': int(fields[1]), 'pgid': int(fields[2]),
            'cpu_percent': float(fields[3]), 'rss_kib': int(fields[4]), 'executable': fields[5]}


def discover_runner(executable, until):
    raw = host_output(['/bin/ps', '-ww', '-axo', 'pid=,comm='], seconds=2, until=until)
    matches = []
    for line in raw.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[1] == str(executable):
            matches.append(int(parts[0]))
    d.require(len(matches) <= 1, 'Ambiguous exact runner process')
    return matches[0] if matches else None


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


def targeted_bytes(bundle, until=None):
    # Only this result bundle, including unfinished Staging. No machine-wide I/O.
    total = count = 0
    started = time.monotonic()
    d.require(until is None or time.time() < until, 'Targeted result-file scan deadline exhausted')
    if bundle.exists():
        for root, _, files in os.walk(bundle):
            for name in files:
                count += 1
                d.require(count <= 100000 and time.monotonic() - started < 2, 'Targeted result-file scan limit exceeded')
                d.require(until is None or time.time() < until, 'Targeted result-file scan deadline exhausted')
                try:
                    total += (Path(root) / name).stat().st_size
                except FileNotFoundError:
                    pass  # XCTest may atomically move a Staging file.
    return {'result_bundle': str(bundle), 'bytes': total, 'files': count}


class Monitor:
    def __init__(self, lane, stage, process, metadata, until, started=None):
        self.lane, self.stage, self.process, self.metadata, self.until = lane, stage, process, metadata, until
        self.directory = d.DIAGNOSTIC / stage
        self.directory.mkdir(parents=True, exist_ok=True)
        began = time.time() if started is None else started
        self.startup_until = min(until, began + 300)
        self.report = dict(d.identity(), stage=stage, xcodebuild_pid=process.pid, monitor_pid=os.getpid(),
                           started=began, startup_deadline=self.startup_until, startup_maximum_seconds=300,
                           status='running', observations=[], samples=[], errors=[], warnings=[],
                           sample_duration_seconds=3, sampling_interval_ms=10, max_sample_processes=4)
        self.runner_pid = None
        self.runner_executable = None
        self.runner_data = None
        self.app_data = None
        self.seen = set()
        self.pending = {}
        self.next_discovery = 0
        self.discovery_attempts = 0
        self.test_started = False
        self.startup_sampled = False
        self.termination_sampled = False
        self.sample_processes = []
        self.write()

    def write(self):
        encoded = json.dumps(self.report, sort_keys=True)
        if encoded != getattr(self, '_last_written', None):
            d.write(self.directory / 'monitor.json', self.report)
            self._last_written = encoded

    def snapshot(self, reason, marker=None):
        until = min(self.until, self.startup_until) if reason.startswith('startup') else self.until
        row = {'reason': reason, 'observation_wall_time': time.time(),
               'observation_monotonic_ns': str(time.monotonic_ns()), 'marker': marker,
               'processes': [], 'result': targeted_bytes(d.BUILD / f'Diagnostic-{self.stage}.xcresult', until)}
        for pid in (self.process.pid, self.runner_pid):
            if pid is not None:
                try:
                    row['processes'].append(process_row(pid, until))
                except (OSError, ValueError, subprocess.SubprocessError) as error:
                    row['processes'].append({'pid': pid, 'unavailable': str(error)})
        self.report['observations'].append(row)

    def sample(self, reason, marker=None):
        until = min(self.until, self.startup_until) if reason.startswith('startup') else self.until
        ledger_path = d.DIAGNOSTIC / 'sample-budget.json'
        ledger = json.loads(ledger_path.read_text()) if ledger_path.exists() else dict(d.identity(), allocated=0, maximum=4)
        d.require(all(ledger.get(k) == v for k, v in d.identity().items()), 'Stale lane sampling budget')
        d.require(ledger.get('maximum') == 4 and type(ledger.get('allocated')) is int
                  and 0 <= ledger['allocated'] <= 4, 'Invalid lane sampling cap')
        targets = [('xcodebuild', self.process.pid)]
        row = process_row(self.process.pid, until)
        d.require(Path(row['executable']).name == 'xcodebuild', 'xcodebuild PID identity changed before sample')
        if self.runner_pid is not None and self.runner_executable is not None:
            row = process_row(self.runner_pid, until)
            d.require(row['executable'] == str(self.runner_executable), 'Runner PID identity changed before sample')
            targets.append(('runner', self.runner_pid))
        else:
            self.report['warnings'].append('Runner PID unavailable at 45-second startup sampling; '
                                           'xcodebuild-only sample cannot prove a runner stall')
        if ledger['allocated'] + len(targets) > ledger['maximum']:
            self.report['errors'].append('Lane-wide 12-second target sampling cap exhausted; no additional sample taken')
            self.write()
            return
        ledger['allocated'] += len(targets)
        d.write(ledger_path, ledger)
        d.require(self.process.poll() is None, 'xcodebuild exited before sample')
        d.require(until - time.time() >= 3, 'Insufficient remaining observation window for a three-second sample')
        for label, pid in targets:
            path = self.directory / f'{reason}-{label}-{pid}.sample.txt'
            entry = dict(reason=reason, pid=pid, process=label, requested_wall_time=time.time(), marker=marker,
                         duration_seconds=3, interval_ms=10, status='running',
                         scope='xcodebuild_only' if len(targets) == 1 else 'xcodebuild_and_runner',
                         runner_sample_unavailable=len(targets) == 1,
                         proves_contemporaneous_stall=False)
            if marker:
                entry['late_marker'] = marker['host_observed_wall_time'] - marker['event_wall_time'] > 2
                entry['proves_contemporaneous_stall'] = False
            # Only these owned sampler process groups can be cancelled by this helper.
            process = subprocess.Popen(['/usr/bin/sample', str(pid), '3', '10', '-file', str(path)],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            self.sample_processes.append((process, entry))
            self.report['samples'].append(entry)
        self.write()
        try:
            for process, entry in self.sample_processes:
                remaining = min(6, until - time.time())
                d.require(remaining > 0, 'Sampling deadline exhausted')
                code = process.wait(timeout=remaining)
                entry.update(finished_wall_time=time.time(), exit_code=code, status='success' if code == 0 else 'failure')
                d.require(code == 0, 'Sampling permission/availability failure')
        finally:
            self.stop_samples()
            self.write()

    def stop_samples(self):
        for process, entry in self.sample_processes:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=2)
                except (OSError, subprocess.SubprocessError) as error:
                    entry['cleanup_error'] = str(error)
                    self.report['errors'].append('Sampler cleanup uncertain: ' + str(error))
        self.sample_processes = []

    def discover(self):
        now = time.time()
        if now < self.next_discovery or self.runner_pid is not None:
            return
        d.require(self.discovery_attempts < 60, 'Runner identity unavailable after 60 bounded observations')
        self.discovery_attempts += 1
        self.next_discovery = now + 5
        # Installation is asynchronous after test-without-building. This bounded
        # observation is not a test retry, launch, or app-interaction command.
        bundle = self.metadata['bundles']['runner']
        try:
            # Cache verified containers within this invocation, so the 60
            # observations use at most 62 helpers rather than 180 repeated calls.
            if self.runner_executable is None:
                installed = container(bundle, 'app', self.startup_until)
                self.runner_executable = installed / bundle['executable']
            if self.runner_data is None:
                self.runner_data = container(bundle, 'data', self.startup_until)
        except subprocess.CalledProcessError as error:
            # Only complete known responses from this exact owned-container
            # lookup are transient. Tool failures, mixed errors and ps failures
            # must not be swallowed as ordinary asynchronous installation.
            identifier = d.owned()['simulator_id']
            expected = ['xcrun', 'simctl', 'get_app_container', identifier, bundle['bundle_id']]
            message = str(error.output or '').strip()
            transitional = error.returncode == 149 and message in {
                'An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):\n'
                + 'Unable to lookup in current state: ' + state for state in ('Shutdown', 'Booting')}
            not_installed = error.returncode == 2 and message == (
                'An error was encountered processing the command (domain=NSPOSIXErrorDomain, code=2):\n'
                'No such file or directory')
            d.require(error.cmd in (expected + ['app'], expected + ['data']) and (transitional or not_installed),
                      'Runner container lookup failed: ' + message)
            self.report.setdefault('container_unavailable', []).append({
                'observed': time.time(), 'message': message[:4096], 'transitional_state': transitional})
            return
        self.runner_pid = discover_runner(self.runner_executable, self.startup_until)
        if self.runner_pid:
            self.report.update(runner_pid=self.runner_pid, runner_executable=str(self.runner_executable),
                               runner_data_container=str(self.runner_data), runner_first_observed_wall_time=time.time())
            self.write()

    def tick(self, allow_sampling=True):
        if allow_sampling:
            d.require(self.test_started or time.time() < self.startup_until,
                      'Runner/test-start evidence missing after bounded 300-second startup window or shared deadline')
        if allow_sampling:
            self.discover()
        now = time.time()
        if self.runner_data:
            folder = self.runner_data / 'Documents/ci-diagnostic'
            d.require(not list(folder.glob('*.error.json')), 'Runner marker export error sidecar')
            paths = list(folder.glob(f'{MARKER_STREAMS.get(self.stage, "cards")}-{self.runner_pid}-*.jsonl'))
            d.require(len(paths) <= 1, 'Ambiguous selected runner session')
            for path in paths:
                rows, _ = read_markers(path)
                for row in rows:
                    valid_marker(row, self.runner_pid, self.metadata, self.stage)
                    key = (row['session_id'], row['sequence'])
                    if key in self.seen:
                        continue
                    self.seen.add(key)
                    observed = dict(row, host_observed_wall_time=time.time(), host_observed_monotonic_ns=str(time.monotonic_ns()))
                    observed['late_marker'] = observed['host_observed_wall_time'] - row['event_wall_time'] > 2
                    if row['phase'] == 'test' and row['edge'] == 'enter':
                        self.test_started = True
                    if row['phase'] == 'app_termination':
                        if row['edge'] == 'enter':
                            self.pending[row['operation_id']] = {'marker': observed, 'checkpoints': {0}}
                            self.snapshot('termination-marker-arrival', observed)
                        else:
                            self.pending.pop(row['operation_id'], None)
            # Only active termination windows get +10/+30 CPU/RSS/result-byte reads.
            for item in self.pending.values():
                marker = item['marker']
                elapsed = now - marker['host_observed_wall_time']
                for seconds in (10, 30):
                    if elapsed >= seconds and seconds not in item['checkpoints']:
                        item['checkpoints'].add(seconds)
                        self.snapshot(f'termination-plus-{seconds}', marker)
                if allow_sampling and now - marker['event_wall_time'] >= 10 and not self.termination_sampled:
                    self.termination_sampled = True
                    self.sample('termination-outstanding', marker)
        if allow_sampling and not self.test_started and not self.startup_sampled and now - self.report['started'] >= 45:
            self.startup_sampled = True
            self.snapshot('startup-no-test-start-45s')
            self.sample('startup-no-test-start-45s')
        self.write()

    def finish(self, code):
        self.stop_samples()
        if not self.runner_pid or not self.test_started:
            self.report['errors'].append('Runner PID or independent test-start marker unavailable')
        self.report.update(finished=time.time(), xcodebuild_exit_code=code,
                           helper_calls=_helper_calls, helper_call_limit=MAX_HELPER_CALLS,
                           discovery_attempts=self.discovery_attempts,
                           status='complete' if not self.report['errors'] else 'inconclusive')
        self.write()


def execute(command, lane, stage):
    metadata = json.loads((d.DIAGNOSTIC / 'built-metadata.json').read_text())
    d.require(all(metadata.get(k) == v for k, v in d.identity().items()), 'Stale built metadata')
    until = d.deadline()
    started = time.time()
    process = subprocess.Popen(command)  # Remains in run-stage's owned process group.
    d.write(d.DIAGNOSTIC / stage / 'launch.json', dict(d.identity(), stage=stage, pid=process.pid,
            parent_pid=os.getpid(), process_group=os.getpgrp(), command=command, started=started, deadline=until))
    if lane == 'visual':
        return process.wait()
    monitor = Monitor(lane, stage, process, metadata, until, started=started)
    previous = {}
    def interrupted(signum, _frame):
        monitor.report['errors'].append('Interrupted: ' + str(signum))
        monitor.stop_samples()
        monitor.write()
        raise SystemExit(128 + signum)
    try:
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous[signum] = signal.signal(signum, interrupted)
        while process.poll() is None:
            monitor.tick()
            time.sleep(.5)
        monitor.tick(allow_sampling=False)
        monitor.finish(process.returncode)
        exported = export_all(checkpoint=stage, until=min(until, time.time() + 35))
        from diagnostic_results import validate_markers
        validate_markers(list((d.DIAGNOSTIC / 'exported/runner').glob('*.jsonl')),
                         dict(d.LANES[lane])[stage], monitor.report, metadata)
        return process.returncode or exported or (1 if monitor.report['errors'] else 0)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        monitor.report['errors'].append(f'{type(error).__name__}: {error}')
        monitor.finish(process.poll())
        # Ask the outer watchdog to stop its OWN group, preserving its normal
        # TERM/grace/KILL and uncertain-cleanup reporting. Never kill by name.
        if process.poll() is None:
            d.require(os.getpgid(os.getpid()) == os.getpid(), 'Not in an owned watchdog process group')
            os.kill(os.getppid(), signal.SIGTERM)
            process.wait(timeout=65)
        return 1
    finally:
        monitor.stop_samples()
        for signum, handler in previous.items():
            signal.signal(signum, handler)


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
                receipt = d.DIAGNOSTIC / f'{kind}-container-metadata.plist'
                shutil.copyfile(meta, receipt)
                output['containers'].append({'kind': kind, 'bundle_id': bundle['bundle_id'],
                                             'path': str(data), 'metadata': str(receipt),
                                             'method': 'exact-owned-device MCM metadata'})
                sources = ((data / 'Documents/ci-diagnostic', ('*.jsonl', '*.error.json'), MAX_MARKER_BYTES)
                           if kind == 'runner' else (data / 'Library/Caches/DailyWhiskersCIDiagnostics', ('reminder-*.json',), MAX_TRACE_BYTES))
                folder, patterns, limit = sources
                destination = d.DIAGNOSTIC / 'exported' / kind
                destination.mkdir(parents=True, exist_ok=True)
                files = [source for pattern in patterns for source in folder.glob(pattern)]
                d.require(len(files) <= 32, 'Unexpected diagnostic export file count')
                for source in files:
                    d.require(time.time() < until and source.stat().st_size <= limit, 'Diagnostic export bound exceeded')
                    d.require(folder.resolve() == folder and source.resolve() == source, 'Unexpected export symlink')
                    shutil.copyfile(source, destination / source.name)
                    output['files'].append({'kind': kind, 'source': str(source), 'path': str(destination / source.name),
                                            'bytes': source.stat().st_size, 'copied_wall_time': time.time()})
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                output['errors'].append(f'{kind}: {type(error).__name__}: {error}')
    except (OSError, ValueError, KeyError, TypeError) as error:
        output['errors'].append(str(error))
    output.update(status='inconclusive' if output['errors'] else 'complete', finished=time.time())
    d.write(path, output)
    return 1 if output['errors'] else 0

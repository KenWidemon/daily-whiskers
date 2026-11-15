#!/usr/bin/env python3
"""Nonqualifying, manual, one-attempt Reminder boundary diagnostic.

Only this branch uses this runner. No ordinary CI collectors or inventory change.
Execution requires a separately approved exact SHA, workflow_dispatch and attempt 1.
Failure (including setup/capture failure) is terminal. Never re-dispatch to repair it.
2700 seconds total execution, including checkout and termination; finalization ends
at 3300 seconds, leaving 300 seconds for bounded artifact upload in the 60-min job.
No explicit download retry; pinned checkout/upload actions and SwiftPM may perform
internal transport retries. No cache, observer, sampler, fallback or additional run.
A pass proves probe observability/nonreproduction only, not a product fix or release.
"""
import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid
import zipfile

BASE = '79ad54a19b398a8222e86f116a5e939b7f009553'
REPOSITORY = 'KenWidemon/daily-whiskers'
REF = 'refs/heads/codex/pr143-denial-reporting-hosted-20261115'
VALIDATED_SOURCE = 'bfde0cbeb3f24473e6ed3fc7dbe8f0f3ed14db79'
CONTRACT = 'ci/reminder_hosted_contract.json'
LIMITS = {'method_seconds':720, 'execution_seconds':2700, 'finalization_seconds':3300,
          'job_seconds':3600, 'export_reserve_seconds':345, 'upload_seconds':300}
SELECTOR = 'DailyWhiskersUITests/ReminderUITests/testDiagnosticInitialEnableProbe'
CASE = 'ReminderUITests/testDiagnosticInitialEnableProbe()'
LOCK = 'DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
PROBE_PATHS = ['DailyWhiskers/Reminders/ReminderModel.swift', 'DailyWhiskers/Reminders/ReminderSettingsView.swift', 'DailyWhiskers/Reminders/ReminderSmoke.swift', 'DailyWhiskers/Reminders/ReminderProbeSnapshot.swift', 'DailyWhiskersUITests/ReminderUITests.swift']
PATCH_SHA = 'e246fe95b7b2efe9fb2b86f82902dfa6784df57fd368e271ee8233c2b2186559'
TYPE = 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro'
RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'
XCODEGEN_SHA = '4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806'
XCODEGEN_URL = 'https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip'
APP_LOG = 'StandardOutputAndStandardError-com.example.kenwidemon.dailywhiskers.txt'
MAX_FILE = 64 * 1024 * 1024
MAX_ARTIFACT = 2 * 1024 * 1024 * 1024

class Invalid(RuntimeError):
    pass

def require(condition, message):
    if not condition:
        raise Invalid(message)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def identity(env):
    expected = {'GITHUB_REPOSITORY': REPOSITORY, 'GITHUB_EVENT_NAME': 'workflow_dispatch',
                'GITHUB_REF': REF, 'GITHUB_RUN_ATTEMPT': '1', 'RUNNER_ARCH': 'ARM64', 'CACHE_EPOCH':'v2'}
    for key, value in expected.items():
        require(env.get(key) == value, 'Wrong ' + key)
    approved = env.get('APPROVED_SHA', '')
    require(re.fullmatch('[0-9a-f]{40}', approved), 'Missing/malformed approved SHA')
    require(env.get('GITHUB_SHA') == approved, 'Event/approved SHA mismatch')
    require(re.fullmatch('[0-9a-f]{64}', env.get('APPROVED_CONTRACT_SHA256','')), 'Missing/malformed approved contract hash')
    for key in ('GITHUB_RUN_ID',):
        require(re.fullmatch('[1-9][0-9]*', env.get(key, '')), 'Invalid ' + key)
    require(env.get('GITHUB_JOB') == 'reminder-boundary', 'Wrong job')
    return {k: env[k] for k in (*expected, 'APPROVED_SHA', 'APPROVED_CONTRACT_SHA256', 'GITHUB_SHA', 'GITHUB_RUN_ID', 'GITHUB_JOB')}

def verify_contract(repo, raw, approved_hash, tracked):
    """Exact separately reviewed contract; no old hosted approval inheritance."""
    require(sha(raw) == approved_hash, 'Approved contract hash mismatch')
    contract = json.loads(raw)
    require(contract.get('schema') == 1 and contract.get('validated_source') == VALIDATED_SOURCE
            and contract.get('ref') == REF and contract.get('selector') == SELECTOR
            and contract.get('limits') == LIMITS, 'Hosted contract identity/limits mismatch')
    hashes = contract.get('files', {})
    require(set(hashes) == set(tracked)-{CONTRACT} and CONTRACT in tracked,
            'Hosted contract source inventory mismatch')
    for file, expected in hashes.items():
        path = repo/file
        require(not Path(file).is_absolute() and '..' not in Path(file).parts
                and not path.is_symlink() and path.resolve().is_relative_to(repo)
                and path.is_file() and sha(path.read_bytes()) == expected,
                'Hosted contract source mismatch: '+file)
    return contract


def validate_container_help(stdout, stderr, exit_code):
    """Reviewed v2 rule: either retained stream, exact syntax, successful exit."""
    require(exit_code == 0, 'Container help command did not succeed')
    require(len(stdout) + len(stderr) <= 64 * 1024, 'Container help exceeds bounded parse size')
    text = stdout.decode('utf-8') + '\n' + stderr.decode('utf-8')
    require(re.search(r'(?m)^\s*Usage: simctl get_app_container <device> <app bundle identifier> \[<container>\]\s*$', text),
            'Container lookup usage does not match the exact device/bundle/container command')
    require(re.search(r"(?m)^\s*data\s+The application's data container\s*$", text),
            'Container lookup does not document the application data container')


class Budget:
    def __init__(self, started, clock=time.monotonic):
        self.clock, self.started = clock, started
        require(isinstance(started, (int, float)) and math.isfinite(started) and started >= 0 and 0 <= clock() - started < 3300, 'Invalid/stale budget origin')
    def remaining(self, final=False):
        return self.started + (3300 if final else 2700) - self.clock()
    def allowance(self, cap, final=False, reserve=75):
        left = self.remaining(final) - reserve
        require(left > 0, 'Absolute deadline exhausted')
        return min(cap, left)

class Commands:
    """Every child owns a new session; only its process group may be signalled."""
    def __init__(self, evidence, cwd, env, budget):
        self.evidence, self.cwd, self.env, self.budget = evidence, cwd, env, budget
        self.phases, self.child, self.settled = [], None, True
    def alive(self, pgid):
        try:
            os.killpg(pgid, 0)
            return True
        except ProcessLookupError:
            return False
    def settle(self, deadline):
        p = self.child
        if p is None:
            return
        pgid = p.pid  # Popen(start_new_session=True), never an inferred/shared group.
        if self.alive(pgid):
            os.killpg(pgid, signal.SIGTERM)
            grace = min(deadline, time.monotonic() + 60)
            while self.alive(pgid) and time.monotonic() < grace:
                p.poll()
                time.sleep(min(.1, max(0, grace-time.monotonic())))
            if self.alive(pgid):
                os.killpg(pgid, signal.SIGKILL)
        left = deadline - time.monotonic()
        if p.poll() is None:
            require(left > 0, 'No owned-child reap time')
            p.wait(timeout=min(15, left))
        self.settled = not self.alive(pgid)
        require(self.settled, 'Owned group not settled; simulator cleanup forbidden')
    def run(self, name, argv, cap=60, final=False, check=True, reserve=75):
        require(self.child is None or self.settled, 'Prior owned process group unresolved; no next phase')
        require(re.fullmatch('[a-z0-9-]+', name), 'Unsafe phase name')
        require(not any(p['name'] == name for p in self.phases), 'Duplicate phase / retry')
        seconds = self.budget.allowance(cap, final, reserve)
        record = {'name': name, 'argv': argv, 'started_at': now(), 'started_tick': time.monotonic(),
                  'timeout_seconds': seconds, 'execution_deadline': self.budget.started+2700,
                  'finalization_deadline': self.budget.started+3300}
        self.phases.append(record)
        save(self.evidence/'phases.json', self.phases)
        out, err = self.evidence/(name+'.stdout'), self.evidence/(name+'.stderr')
        primary = None
        try:
            with out.open('xb') as stdout, err.open('xb') as stderr:
                self.child = subprocess.Popen(argv, cwd=self.cwd, env=self.env, stdout=stdout, stderr=stderr, start_new_session=True)
                self.settled = False
                record['owned_pgid'] = self.child.pid
                save(self.evidence/'phases.json', self.phases)
                try:
                    record['raw_exit'] = self.child.wait(timeout=seconds)
                except BaseException as exc:
                    primary = exc
                    record['primary_error'] = type(exc).__name__+': '+str(exc)
                    record['timed_out'] = isinstance(exc, subprocess.TimeoutExpired)
                finally:
                    try:
                        self.settle(self.budget.started + (3300 if final else 2700))
                    except Exception as exc:
                        self.settled = False
                        record['settlement_error'] = type(exc).__name__+': '+str(exc)
                    record['raw_exit'] = self.child.poll()  # None stays unknown, never invent an exit.
        finally:
            record['finished_at'], record['finished_tick'] = now(), time.monotonic()
            record['group_settled'] = self.settled
            save(self.evidence/'phases.json', self.phases)
        if primary is not None:
            raise primary
        require(self.settled, name + ' owned process settlement failed')
        if check:
            require(record['raw_exit'] == 0, name + ' failed: ' + str(record['raw_exit']))
        require(out.stat().st_size <= MAX_FILE, name + ' output too large to parse; raw retained')
        return out.read_bytes()

def common(build):
    return ['-project', 'DailyWhiskers.xcodeproj', '-clonedSourcePackagesDirPath', str(build/'SourcePackages'),
            '-onlyUsePackageVersionsFromResolvedFile', '-disableAutomaticPackageResolution', 'CODE_SIGNING_ALLOWED=NO']

def test_command(build, bundle, uid):
    return ['xcodebuild', 'test', *common(build), '-scheme', 'DailyWhiskersInteraction', '-configuration', 'Debug',
            '-destination', 'platform=iOS Simulator,id='+uid+',arch=arm64', '-derivedDataPath', str(build/'DerivedData'),
            '-resultBundlePath', str(bundle), '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1',
            '-only-testing:'+SELECTOR, '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '720',
            '-maximum-test-execution-time-allowance', '720', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING DW_REMINDER_ENABLE_PROBE']

def flat(data):
    return {d['udid']: dict(d, runtime=rt) for rt, devices in data['devices'].items() for d in devices}

def stable(devices):
    keys = ('udid', 'name', 'deviceTypeIdentifier', 'runtime', 'isAvailable', 'state')
    return {uid: {k: d.get(k) for k in keys} for uid, d in devices.items()}

def owns(uid, name, before, current):
    d = current.get(uid, {})
    return bool(uid and uid not in before and d.get('name') == name and d.get('deviceTypeIdentifier') == TYPE and d.get('runtime') == RUNTIME)

def toolchain(xcode, sdk, arch, runtimes):
    require(xcode.strip().splitlines() == ['Xcode 27.2', 'Build version 27B52'], 'Wrong observed Xcode')
    require(sdk.strip() == '27.2' and arch.strip() == 'arm64', 'Wrong SDK/architecture')
    found = [r for r in runtimes['runtimes'] if r['identifier'] == RUNTIME]
    require(len(found) == 1 and found[0]['isAvailable'] and found[0]['version'] == '27.0' and found[0]['buildversion'] == '24A434', 'Wrong runtime')

# Legacy structured-object helpers. Raw CAS directory content does not include refs;
# graph supplies its ordered refs, cross-checked against official raw directory JSON.
def unwrap(value):
    if isinstance(value, dict):
        if '_value' in value:
            return value['_value']
        if '_values' in value:
            return [unwrap(v) for v in value['_values']]
        return {k: unwrap(v) for k, v in value.items() if k != '_type'}
    return value

def walk(value):
    yield value
    if isinstance(value, dict):
        for v in value.values():
            yield from walk(v)
    elif isinstance(value, list):
        for v in value:
            yield from walk(v)

def parse_graph(text):
    roots, stack = [], []
    for line in text.splitlines():
        stripped, indent = line.lstrip(), len(line)-len(line.lstrip())
        if stripped.startswith('* '):
            node = {'kind': stripped[2:], 'entries': [], 'children': []}
            while stack and stack[-1][0] >= indent:
                stack.pop()
            (stack[-1][1]['children'] if stack else roots).append(node)
            stack.append((indent, node))
        elif stripped.startswith('- Id: '):
            require(stack, 'Graph ID without node')
            stack[-1][1]['ref'] = stripped[6:]
        elif stripped.startswith('+ '):
            match = re.fullmatch(r'\+ (.*) \((directory|plainFile)\)', stripped)
            require(match is not None and stack, 'Unrecognized graph entry')
            stack[-1][1]['entries'].append({'name': match[1], 'type': 2 if match[2] == 'directory' else 1})
    require(len(roots) == 1, 'Ambiguous graph root')
    return roots[0]

class Collector:
    def __init__(self, commands, bundle, output):
        self.c, self.bundle, self.output = commands, bundle, output
        self.chain, self.index = [], 0
        self.final_reserve = 75
        self.diagnostic_context = None
        self.diagnostic_error = None
    def get(self, argv):
        self.index += 1
        return self.c.run('extract-'+str(self.index), ['xcrun', 'xcresulttool', *argv, '--path', str(self.bundle)], 60, final=True, reserve=self.final_reserve)
    def obj(self, ref=None, raw=False):
        args = ['get', 'object', '--legacy', '--format', 'raw' if raw else 'json']
        if ref:
            args += ['--id', ref]
        data = self.get(args)
        return data if raw else unwrap(json.loads(data))
    def directory(self, node):
        entries = json.loads(self.obj(node['ref'], raw=True))
        require(entries == node['entries'] and len(entries) == len(node['children']), 'Directory/graph reference mismatch')
        row = {'ref': node['ref'], 'entries': [dict(e, ref=c['ref']) for e, c in zip(entries, node['children'])]}
        self.chain.append(row)
        save(self.output/'app-log-reference-chain.json', self.chain)
        return [(e, c) for e, c in zip(entries, node['children'])]
    def session_context(self):
        """Resolve the existing unique Session independently of app stdout."""
        if self.diagnostic_context is not None:
            return self.diagnostic_context
        if self.diagnostic_error is not None:
            raise Invalid('Prior Session extraction failed; no retry: '+self.diagnostic_error)
        try:
            return self._session_context_once()
        except (Exception, KeyboardInterrupt) as exc:
            self.diagnostic_error = type(exc).__name__+': '+str(exc)
            raise

    def _session_context_once(self):
        root = self.obj()
        save(self.output/'invocation.json', root)
        actions = root.get('actions', [])
        candidates = [a['actionResult'] for a in actions if a.get('actionResult', {}).get('diagnosticsRef')]
        require(len(candidates) == 1, 'Ambiguous action diagnostics')
        result = candidates[0]
        ref = result['diagnosticsRef']['id']
        graph = self.get(['graph', '--legacy', '--id', ref]).decode()
        (self.output/'diagnostics-reference-graph.txt').write_text(graph)
        node = parse_graph(graph)
        require(node['ref'] == ref, 'Root diagnostic ref mismatch')
        choices = [(e, c) for e, c in self.directory(node) if e['type'] == 2 and e['name'].startswith('DailyWhiskersUITests-')]
        require(len(choices) == 1 and re.fullmatch(r'DailyWhiskersUITests-[A-F0-9-]+-Configuration-Test Scheme Action-Iteration-1', choices[0][0]['name']), 'Additional/ambiguous/missing test iteration or configuration directory')
        choices = [(e, c) for e, c in self.directory(choices[0][1]) if e['type'] == 2 and e['name'].startswith('DailyWhiskersUITests-')]
        require(len(choices) == 1 and re.fullmatch(r'DailyWhiskersUITests-[A-F0-9-]+', choices[0][0]['name']), 'Additional/ambiguous/missing test session directory')
        leaves = self.directory(choices[0][1])
        app = [(e, c) for e, c in leaves if e['type'] == 1 and e['name'] == APP_LOG]
        sessions = [(e, c) for e, c in leaves if e['type'] == 1 and e['name'].startswith('Session-DailyWhiskersUITests-') and e['name'].endswith('.log')]
        require(len(sessions) == 1, 'Ambiguous/missing Session log')
        session = self.obj(sessions[0][1]['ref'], raw=True)
        (self.output/'Session.log').write_bytes(session)
        save(self.output/'session-provenance.json', {'diagnostics_ref': ref,
             'session_ref': sessions[0][1]['ref'], 'session_sha256': sha(session),
             'session_bytes': len(session), 'same_bundle': str(self.bundle)})
        self.diagnostic_context = (result, ref, app, sessions, session)
        return self.diagnostic_context

    def launch_identity(self):
        return session_identity(self.session_context()[4].decode('utf-8'))

    def collect(self, expected_uid=None, source_valid=False):
        summary = json.loads(self.get(['get', 'test-results', 'summary']))
        tests = json.loads(self.get(['get', 'test-results', 'tests']))
        save(self.output/'summary.json', summary)
        save(self.output/'tests.json', tests)
        result, ref, app, sessions, session = self.session_context()
        require(len(app) == 1, 'Ambiguous/missing app stdout')
        raw = self.obj(app[0][1]['ref'], raw=True)
        (self.output/'app-stdout-stderr.txt').write_bytes(raw)
        (self.output/'Session.log').write_bytes(session)
        provenance = {'diagnostics_ref': ref, 'app_ref': app[0][1]['ref'], 'app_sha256': sha(raw), 'app_bytes': len(raw),
                      'session_ref': sessions[0][1]['ref'], 'session_sha256': sha(session), 'same_bundle': str(self.bundle)}
        save(self.output/'app-log-provenance.json', provenance)
        tree = self.obj(result['testsRef']['id'])
        save(self.output/'legacy-tests.json', tree)
        test_refs = [x for x in walk(tree) if isinstance(x, dict) and x.get('identifier') == CASE and 'summaryRef' in x]
        activities = None
        all_refs = [x for x in walk(tree) if isinstance(x,dict) and 'summaryRef' in x]
        if len(test_refs) == 1 and len(all_refs) == 1:
            activities = self.obj(test_refs[0]['summaryRef']['id'])
            save(self.output/'test-activities.json', activities)
        verdict = validate_capture(raw.decode(errors='replace'), session.decode(errors='replace'), summary, tests, activities, expected_uid, source_valid)
        verdict['legacy_execution_count'] = len(all_refs)
        if len(all_refs) != 1 or len(test_refs) != 1:
            verdict['capture_valid'] = verdict['negative_marker_inference_qualified'] = False
            verdict['capture_errors'].append('Legacy case/execution count does not equal one selected case')
        verdict['provenance'] = provenance
        save(self.output/'collector-verdict.json', verdict)
        return verdict

def session_identity(session):
    """No stdout, guessed UUID, relaunch, or fallback identity source."""
    starts = re.findall(r"(?m)^Test Case '-\[([^\]]+)\]' started\.$", session)
    require(starts == ['DailyWhiskersUITests.ReminderUITests testDiagnosticInitialEnableProbe'],
            'Session selected-case identity is ambiguous/missing')
    pids = re.findall(r'Launched app with identifier: com\.example\.kenwidemon\.dailywhiskers \(pid = (\d+)\)', session)
    runs = re.findall(r'"DW_REMINDER_TEST_ID"\s*=\s*"([^"\n]*)"', session)
    require(len(pids) == 1 and int(pids[0]) > 0 and runs and len(set(runs)) == 1,
            'Session launch/fixture identity is ambiguous/missing')
    require(str(uuid.UUID(runs[0])).upper() == runs[0], 'Noncanonical Session UUID')
    return {'run': runs[0], 'pid': int(pids[0])}

def wall_datetime(value):
    # Xcode emits offsets such as -0500, which Python 3.9 fromisoformat rejects.
    value = re.sub(r'([+-]\d{2})(\d{2})$', r'\1:\2', value)
    parsed = datetime.datetime.fromisoformat(value)
    require(parsed.tzinfo is not None, 'Wall timestamp lacks timezone')
    return parsed

def session_records(session, start, finish):
    """Date-less Session records are accepted only inside a same-date wall interval.

    No subtraction from app uptime is performed. Cross-midnight/ambiguous evidence
    is conservatively inconclusive rather than assigning guessed dates.
    """
    require(start.date() == finish.date(), 'Session wall interval crosses date; manual review required')
    values = []
    matches = list(re.finditer(r'(?m)^(\d\d:\d\d:\d\d\.\d+) ', session))
    for i, match in enumerate(matches):
        stamp = datetime.datetime.combine(start.date(), datetime.time.fromisoformat(match[1]), start.tzinfo)
        if start <= stamp <= finish:
            end = matches[i+1].start() if i+1 < len(matches) else len(session)
            values.append({'at':stamp.isoformat(),'text':session[match.start():end]})
    return values

def passive_delivery(session, ready, tap, pid):
    start = wall_datetime(tap['start'])
    finish = wall_datetime(tap['finish'])
    require(wall_datetime(ready) <= start <= finish, 'Readiness/tap ordering')
    before = session_records(session,wall_datetime(ready),start)
    during = session_records(session,start,finish)
    # A finished predicate activity is not a successful predicate. Follow the exact
    # waiter ID from entry through its successful completion before the tap.
    waits = []
    for i, row in enumerate(before):
        text = row['text']
        if 'entering wait loop' in text and 'Expect predicate `value == "0"` for object "reminder-enabled" Switch' in text:
            match = re.search(r'<XCTWaiter: ([^>]+)>',text)
            if match:
                completed = [j for j in range(i+1,len(before)) if 'Returning result XCTWaiterResultCompleted for synchronous waiter <XCTWaiter: '+match[1]+'>' in before[j]['text']]
                if completed:
                    waits.append({'entry':row,'completion':before[completed[0]]})
    require(len(waits) == 1, 'Missing unique successful pre-attempt Off waiter')
    synthesis = []
    for i, row in enumerate(during):
        text = row['text']
        if 'entering wait loop' in text and 'expectations: `synthesizing event`' in text:
            match = re.search(r'<XCTWaiter: ([^>]+)>',text)
            if match:
                completed = [j for j in range(i+1,len(during)) if 'Returning result XCTWaiterResultCompleted for synchronous waiter <XCTWaiter: '+match[1]+'>' in during[j]['text']]
                if completed:
                    j = completed[0]
                    ack = [r for r in during[i+1:j] if re.search(r'Received kAXUserTestingNotification from AX element pid: '+str(pid)+r',[^\n]*: \{\s*event = TouchEventsCompleted;',r['text'])]
                    future = [r for r in during[j:] if 'Event synthesis future completed in ' in r['text']]
                    if ack and future:
                        synthesis.append({'entry':row,'same_pid_acknowledgments':ack,'completion':during[j],'future':future[0]})
    require(len(synthesis) == 1, 'Missing unique same-PID native acknowledgment / successful synthesis chain')
    return {'off_waiter':waits[0],'native_delivery':synthesis[0]}

def terminal_witness(session, summary, cases, delivery):
    """A terminal record qualifies absence, not validity of earlier positive markers."""
    endings = list(re.finditer(r"(?m)^Test Case '-\[DailyWhiskersUITests\.ReminderUITests testDiagnosticInitialEnableProbe\]' (passed|failed) \(([0-9]+(?:\.[0-9]+)?) seconds\)\.$", session))
    require(endings, 'Missing terminal Session case witness; tail may be truncated')
    states = {(m[1],float(m[2])) for m in endings}
    require(len(states) == 1, 'Contradictory Session terminal echoes')
    state, duration = next(iter(states))
    require(len(cases) == 1 and cases[0].get('result') == state.capitalize() and summary.get('result') == state.capitalize(), 'Session/result terminal outcome disagreement')
    require(summary.get('passedTests') == int(state == 'passed') and summary.get('failedTests') == int(state == 'failed'), 'Terminal result counts disagree')
    if 'durationInSeconds' in cases[0]:
        require(f"{cases[0]['durationInSeconds']:.3f}" == f"{duration:.3f}", 'Terminal duration disagreement')
    require(delivery is not None, 'No qualified native delivery for terminal ordering')
    future = delivery['native_delivery']['future']['text']
    require(session.count(future) == 1 and all(m.start() > session.index(future) for m in endings), 'Terminal case witness is not after native delivery')
    return {'outcome':state,'duration_seconds':duration,'consistent_echoes':len(endings),'records':[m[0] for m in endings]}

def validate_capture(raw, session, summary, tests, activities, expected_uid, source_valid):
    errors, records, inference_errors = [], [], []
    fields = {'schema','run','pid','seq','tick','stage','id','command','requested','enabled','authorization','queued','hasCoverage','hasMessage','storageBlocked','cleanupPending','busy','loaded','operations'}
    bools = {'enabled','hasCoverage','hasMessage','storageBlocked','cleanupPending','busy','loaded'}
    ints = {'schema','pid','seq','id','requested','queued','operations'}
    for line in raw.splitlines():
        if 'DWReminderEnableProbe ' not in line:
            continue
        try:
            prefix, marker = line.split('DWReminderEnableProbe ', 1)
            pairs = marker.split()
            require(all(p.count('=') == 1 for p in pairs), 'Malformed marker')
            record = dict(p.split('=', 1) for p in pairs)
            require(len(pairs) == len(fields) and set(record) == fields, 'Marker fields missing/duplicate')
            for f in bools:
                require(record[f] in ('true', 'false'), 'Invalid boolean')
                record[f] = record[f] == 'true'
            for f in ints:
                record[f] = int(record[f])
            record['tick'] = float(record['tick'])
            require(math.isfinite(record['tick']) and record['tick'] >= 0, 'Invalid app tick')
            stamp = re.match(r'(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+[+-]\d{4})', prefix)
            require(stamp is not None, 'Missing app wall timestamp')
            record['wall_timestamp'] = datetime.datetime.strptime(stamp[1], '%Y-%m-%d %H:%M:%S.%f%z').isoformat()
            require(record['schema'] == 1 and str(uuid.UUID(record['run'])).upper() == record['run'], 'Schema/fixture UUID')
            require(re.search(r'DailyWhiskers\['+str(record['pid'])+r':\d+\]', prefix), 'App prefix PID mismatch')
            require(record['stage'] in ('ready','bindingSetter','sendEntry','statusPublished','sendComplete'), 'Unknown stage')
            require(record['command'] in ('none','enable','refresh','time'), 'Unknown command')
            records.append(record)
        except (Invalid, ValueError, KeyError) as exc:
            errors.append(str(exc))
    starts = re.findall(r"(?m)^Test Case '-\[([^\]]+)\]' started\.$", session)
    if starts != ['DailyWhiskersUITests.ReminderUITests testDiagnosticInitialEnableProbe']:
        errors.append('Session case-start count/identity does not equal one selected case')
    if not source_valid:
        errors.append('Source/approved-run provenance not established by this extraction')
    cases = [x for x in walk(tests) if isinstance(x, dict) and x.get('nodeType') == 'Test Case']
    case_valid = len(cases) == 1 and cases[0].get('nodeIdentifier') == CASE
    if not case_valid or summary.get('totalTestCount') != 1 or summary.get('skippedTests') != 0 or summary.get('expectedFailures') != 0:
        errors.append('Wrong/ambiguous case or count')
    devices = tests.get('devices', [])
    device_valid = len(devices) == 1 and devices[0].get('modelName') == 'iPhone 17 Pro' and devices[0].get('architecture') == 'arm64' and devices[0].get('osVersion') == '27.0' and devices[0].get('osBuildNumber') == '24A434' and devices[0].get('platform') == 'iOS Simulator'
    if not device_valid or not expected_uid or devices[0].get('deviceId') != expected_uid:
        errors.append('Wrong/unknown owned device')
    if not records:
        errors.append('No probe readiness/markers')
    else:
        if len({(r['run'],r['pid']) for r in records}) != 1:
            errors.append('Ambiguous fixture/PID')
        if sum(r['stage'] == 'ready' for r in records) != 1 or records[0]['stage'] != 'ready' or [r['seq'] for r in records] != list(range(1,len(records)+1)):
            errors.append('Missing readiness or sequence gap')
        if any(b['tick'] < a['tick'] for a,b in zip(records,records[1:])):
            errors.append('Nonmonotonic app ticks')
        pid, runid = records[0]['pid'], records[0]['run']
        if re.findall(r'Launched app with identifier: com\.example\.kenwidemon\.dailywhiskers \(pid = (\d+)\)', session) != [str(pid)] or set(re.findall(r'"DW_REMINDER_TEST_ID"\s*=\s*"([A-F0-9-]+)"', session)) != {runid}:
            errors.append('Session launch/fixture identity missing')
    commands = {}
    for r in records:
        if r['stage'] in ('ready','bindingSetter'):
            if r['id'] != 0:
                errors.append('Noncommand stage has send ID')
            continue
        group = commands.setdefault(r['id'], [])
        group.append(r)
    for ident, group in commands.items():
        stages = [r['stage'] for r in group]
        if ident <= 0 or stages not in (['sendEntry'],['sendEntry','statusPublished'],['sendEntry','statusPublished','sendComplete']) or len({(r['command'],r['requested']) for r in group}) != 1:
            errors.append('Invalid command stage relationship')
    entries = [r['id'] for r in records if r['stage'] == 'sendEntry']
    if entries != list(range(1,len(entries)+1)):
        errors.append('Send entry ID gap/order')
    native = [x for x in walk(activities or {}) if isinstance(x,dict) and x.get('title') == 'Tap Switch (First Match)']
    pre = [x for x in walk(activities or {}) if isinstance(x,dict) and 'reminder-enabled' in x.get('title','') and 'value == "0"' in x.get('title','')]
    delivery = None
    if len(native) != 1 or not native[0].get('finish') or not pre:
        inference_errors.append('Missing unique completed native tap or pre-attempt Off evidence')
    else:
        try:
            tap_start = wall_datetime(native[0]['start'])
            require(any(wall_datetime(p['finish']) <= tap_start for p in pre), 'Off evidence is not pre-attempt')
            require(records and records[0]['stage'] == 'ready' and wall_datetime(records[0]['wall_timestamp']) <= tap_start, 'Ready is not pre-attempt')
            require(not any(x.get('failureSummaryIDs') for x in walk(native[0]) if isinstance(x,dict)), 'Native activity has failure summaries')
            delivery = passive_delivery(session,records[0]['wall_timestamp'],native[0],records[0]['pid'])
        except (Invalid, KeyError, ValueError) as exc:
            inference_errors.append(str(exc))
    terminal = None
    try:
        terminal = terminal_witness(session,summary,cases,delivery)
    except (Invalid,KeyError,ValueError) as exc:
        inference_errors.append(str(exc))
    setters = [r for r in records if r['stage'] == 'bindingSetter' and r['command'] == 'enable' and r['requested'] == 1]
    enable = [group for group in commands.values() if group[0]['command'] == 'enable' and group[0]['requested'] == 1]
    if len(setters) > 1 or len(enable) > 1:
        errors.append('Multiple enable attempts')
    if not setters:
        outcome = 'binding setter not observed; not infrastructure proof or definite noninvocation'
    elif not enable:
        outcome = 'observed binding-to-command gap; Task cause not established'
    elif enable[0][-1]['stage'] != 'sendComplete':
        outcome = 'unfinished enable command evidence; distinguish timeout/crash/capture loss/concurrent refresh'
    elif not enable[0][-1]['enabled']:
        outcome = 'model received/assigned Off; preserve all status flags'
    elif case_valid and cases[0].get('result') == 'Passed':
        outcome = 'hosted probe observability/nonreproduction only; no fix or acceptance'
    else:
        outcome = 'enable completed On; UI discrepancy requires failed UI-Off assertion and no later status reversal review'
    return {'capture_valid': not errors, 'negative_marker_inference_qualified': not errors and not inference_errors,
            'negative_inference_errors': inference_errors, 'passive_delivery': delivery, 'terminal_witness': terminal,
            'capture_errors': errors, 'outcome': outcome, 'records': records, 'commands': commands,
            'actual_cases': cases, 'session_case_starts': starts, 'native_taps': native, 'pre_attempt_off_activities': pre,
            'limitations': ['A contiguous prefix does not prove an unrecorded tail never occurred.',
                           'Missing completion does not invalidate earlier positive evidence.',
                           'Send IDs are entry order, not enqueue order. Refresh events may interleave.',
                           'App monotonic times are one clock domain; no cross-domain subtraction or performance threshold.',
                           'Fake permission establishes neither OS delivery nor durable persistence.',
                           'Logging/initial observation may perturb timing; four hosted failures and release gates remain open.']}

def manifest(root, budget):
    files, total = {}, 0
    for path in sorted(root.rglob('*')):
        require(budget.remaining(True) > 15, 'Finalization hashing deadline')
        require(not path.is_symlink(), 'Artifact symlink')
        if not path.is_file() or path.name == 'evidence-manifest.json':
            continue
        size = path.stat().st_size
        total += size
        require(total <= MAX_ARTIFACT, 'Artifact exceeds 2 GiB cap; no upload eligibility')
        h = hashlib.sha256()
        with path.open('rb') as handle:
            while True:
                require(budget.remaining(True) > 15, 'Finalization hashing deadline')
                chunk = handle.read(1024*1024)
                if not chunk:
                    break
                h.update(chunk)
        files[str(path.relative_to(root))] = {'bytes': size, 'sha256': h.hexdigest()}
    save(root/'evidence-manifest.json', {'files': files, 'total_bytes': total, 'cap_bytes': MAX_ARTIFACT,
         'retention_days': 30, 'artifact_api_id_and_digest': 'Record from upload step, then download and verify archive/checksums before retention claim'})

def execute(env):
    import reminder_snapshot as snapshot
    ident = identity(env)
    repo = Path(env['GITHUB_WORKSPACE']).resolve()
    root = Path(env['RUNNER_TEMP'])/'reminder-boundary'
    receipt = json.loads((root/'budget.json').read_text())
    require(receipt['sha'] == ident['GITHUB_SHA'] and receipt['run_id'] == ident['GITHUB_RUN_ID'] and receipt['attempt'] == '1' and receipt['contract_sha256'] == ident['APPROVED_CONTRACT_SHA256'], 'Budget identity mismatch')
    budget = Budget(receipt['started_monotonic'])
    require(root.resolve() == root, 'Root symlink')
    evidence = root/'evidence'
    evidence.mkdir(exist_ok=False)
    save(evidence/'budget.json', dict(receipt, limits=LIMITS))
    build = root/'build'
    build.mkdir(exist_ok=False)
    env = dict(env, DEVELOPER_DIR='/Applications/Xcode_27.2.app/Contents/Developer', GIT_OPTIONAL_LOCKS='0')
    c = Commands(evidence, repo, env, budget)
    status = {'started_at': now(), 'identity': ident, 'test_command_planned': False, 'test_process_spawned': False, 'test_invocations': 0, 'raw_test_exit': None, 'primary_error': None, 'cleanup_errors': []}
    before, uid, name, attempted, source_valid = None, None, None, False, False
    code = 1
    def stopped(sig, frame):
        status['signal'] = sig
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        raise InterruptedError('Supervisor signal '+str(sig))
    old = {s: signal.signal(s, stopped) for s in (signal.SIGTERM, signal.SIGINT)}
    bundle = evidence/'ReminderBoundary.xcresult'
    lock_sha = None
    try:
        head = c.run('source-head',['git','rev-parse','HEAD']).decode().strip()
        require(head == ident['APPROVED_SHA'], 'Checkout/approved SHA mismatch')
        require(not c.run('source-status',['git','status','--porcelain=v1','--untracked-files=all']), 'Dirty initial checkout')
        patch = c.run('probe-patch',['git','diff','--binary',BASE,'HEAD','--',*PROBE_PATHS])
        require(sha(patch) == PATCH_SHA, 'Probe patch changed')
        tree = c.run('source-tree',['git','rev-parse','HEAD^{tree}']).decode().strip()
        files = [f for f in c.run('source-files',['git','ls-files','-z']).decode().split('\0') if f]
        require(c.run('source-parent',['git','show','-s','--format=%P','HEAD']).decode().strip() == VALIDATED_SOURCE, 'Wrong validated source parent')
        contract_raw = (repo/CONTRACT).read_bytes()
        verify_contract(repo,contract_raw,ident['APPROVED_CONTRACT_SHA256'],files)
        (evidence/'approved-contract.raw.json').write_bytes(contract_raw)
        save(evidence/'source.json', {'commit':head,'tree':tree,'base':BASE,'probe_patch_sha256':sha(patch),
            'files':{f:sha((repo/f).read_bytes()) for f in files}, 'selector':SELECTOR,
            'contract_sha256':sha(contract_raw), 'validated_source':VALIDATED_SOURCE})
        source_valid = True
        lock_sha = sha((repo/LOCK).read_bytes())
        xcode = c.run('toolchain-xcode',['xcodebuild','-version']).decode()
        sdk = c.run('toolchain-sdk',['xcrun','--sdk','iphonesimulator','--show-sdk-version']).decode()
        arch = c.run('toolchain-arch',['uname','-m']).decode()
        runtimes = json.loads(c.run('toolchain-runtimes',['xcrun','simctl','list','runtimes','-j']))
        toolchain(xcode,sdk,arch,runtimes)
        save(evidence/'toolchain.json',{'xcode':xcode,'sdk':sdk,'arch':arch,'runtimes':runtimes,'image_os':env.get('ImageOS'),'image_version':env.get('ImageVersion')})
        help_stdout = c.run('verify-container-interface',['xcrun','simctl','help','get_app_container'],30)
        help_stderr_path = evidence/'verify-container-interface.stderr'
        require(help_stderr_path.stat().st_size <= 64*1024, 'Container help stderr exceeds bounded parse size')
        validate_container_help(help_stdout, help_stderr_path.read_bytes(), c.phases[-1]['raw_exit'])
        before = flat(json.loads(c.run('devices-before',['xcrun','simctl','list','devices','-j'])))
        save(evidence/'devices-before.json', before)
        archive = build/'xcodegen.zip'
        c.run('download-xcodegen',['curl','--fail','--location','--retry','0','--connect-timeout','30','--max-time','120','--output',str(archive),XCODEGEN_URL],125)
        require(sha(archive.read_bytes()) == XCODEGEN_SHA, 'XcodeGen archive checksum')
        # Extraction is bounded by the same deadline and validates archive paths first.
        with zipfile.ZipFile(archive) as z:
            require(sum(i.file_size for i in z.infolist()) < 200*1024*1024, 'XcodeGen archive too large')
            for i in z.infolist():
                require(not Path(i.filename).is_absolute() and '..' not in Path(i.filename).parts and ((i.external_attr >> 16) & 0o170000) != 0o120000, 'Unsafe XcodeGen ZIP member')
        c.run('unzip-xcodegen',['unzip','-q',str(archive),'-d',str(build/'xcodegen')],60)
        generator = build/'xcodegen/xcodegen/bin/xcodegen'
        require(c.run('xcodegen-version',[str(generator),'--version']).decode().strip() == 'Version: 2.46.0', 'Wrong XcodeGen version')
        fixture = repo/'DailyWhiskers/Resources/GoogleService-Info.plist'
        require(not fixture.exists() and not fixture.is_symlink(), 'Unexpected Firebase file')
        fixture.write_bytes((repo/'ci/firebase-test-config.plist').read_bytes())
        save(evidence/'fixture.json', {'fake_sha256':sha(fixture.read_bytes()),'lock_sha256':lock_sha})
        c.run('generate-project',[str(generator),'generate'],120)
        require(sha((repo/LOCK).read_bytes()) == lock_sha, 'XcodeGen changed lock')
        (build/'SourcePackages').mkdir(exist_ok=False)
        (build/'DerivedData').mkdir(exist_ok=False)
        c.run('resolve-once',['xcodebuild','-resolvePackageDependencies',*common(build),'-scheme','DailyWhiskers','-derivedDataPath',str(build/'DerivedData')],900)
        require(sha((repo/LOCK).read_bytes()) == lock_sha, 'Resolution changed lock')
        pins = {p['identity']:p['state']['revision'] for p in json.loads((repo/LOCK).read_text())['pins']}
        state = json.loads((build/'SourcePackages/workspace-state.json').read_text())
        checked = {}
        for number, dep in enumerate(state['object']['dependencies']):
            package = dep['packageRef']['identity']
            checkout = build/'SourcePackages/checkouts'/dep['subpath']
            require(checkout.resolve().is_relative_to(build/'SourcePackages/checkouts'), 'External dependency checkout')
            head = c.run('package-head-'+str(number), ['git','-C',str(checkout),'rev-parse','HEAD']).decode().strip()
            require(head == pins.get(package) == dep['state']['checkoutState']['revision'], 'Dependency pin mismatch')
            checked[package] = head
        require(checked == pins, 'Incomplete dependency pin evidence')
        save(evidence/'package-pins.json',checked)
        name = 'DW143 Hosted Reminder '+env['GITHUB_RUN_ID']+' '+uuid.uuid4().hex
        save(evidence/'ownership-intent.json',{'name':name,'type':TYPE,'runtime':RUNTIME,'baseline_ids':sorted(before)})
        attempted = True
        uid = c.run('create-simulator',['xcrun','simctl','create',name,TYPE,RUNTIME],45).decode().strip()
        require(str(uuid.UUID(uid)).upper() == uid, 'Invalid created UUID')
        current = flat(json.loads(c.run('devices-created',['xcrun','simctl','list','devices','-j'])))
        require(owns(uid,name,before,current), 'Ownership not proved')
        save(evidence/'ownership.json',{'udid':uid,'name':name,'type':TYPE,'runtime':RUNTIME})
        c.run('boot-simulator',['xcrun','simctl','boot',uid],45)
        c.run('wait-bootstatus',['xcrun','simctl','bootstatus',uid,'-b'],180)
        ready = flat(json.loads(c.run('devices-ready',['xcrun','simctl','list','devices','-j'])))
        require(owns(uid,name,before,ready) and ready[uid]['state'] == 'Booted' and ready[uid]['isAvailable'], 'Owned device not ready')
        require(stable({k:v for k,v in ready.items() if k!=uid}) == stable(before), 'Preexisting devices changed')
        command = test_command(build,bundle,uid)
        save(evidence/'selected-command.json',{'command':command,'selector':SELECTOR,'retry':False})
        status['test_command_planned'] = True
        save(evidence/'status.json',status)
        c.run('xcodebuild-test',command,2700,check=False)
        status['raw_test_exit'] = c.phases[-1]['raw_exit']
        code = 0 if status['raw_test_exit'] == 0 else 1
    except BaseException as exc:
        status['primary_error'] = type(exc).__name__+': '+str(exc)
    finally:
        for s in old:
            signal.signal(s,signal.SIG_IGN)
        # Child termination is always charged to the original execution budget.
        try:
            c.settle(budget.started+2700)
        except Exception as exc:
            status['cleanup_errors'].append(str(exc))
        if status['raw_test_exit'] is None:
            phases = [p for p in c.phases if p['name'] == 'xcodebuild-test']
            if phases:
                status['raw_test_exit'] = phases[0].get('raw_exit')
        test_phases = [p for p in c.phases if p['name'] == 'xcodebuild-test']
        status['test_process_spawned'] = bool(test_phases and test_phases[0].get('owned_pgid'))
        status['test_invocations'] = int(status['test_process_spawned'])
        cleanup = {'verified':False,'owned_uuid':uid,'creation_attempted':attempted}
        export = {'exported':False, 'error':'No verified owned device/result for prefix export'}
        collector = Collector(c,bundle,evidence) if c.settled else None
        try:
            require(c.settled,'Unsettled owned group; no simulator cleanup')
            current = flat(json.loads(c.run('cleanup-snapshot',['xcrun','simctl','list','devices','-j'],45,final=True)))
            if attempted and uid is None:
                matches = [k for k in current if owns(k,name,before,current)]
                require(len(matches) == 1,'Uncertain create outcome; no guessed deletion')
                uid = matches[0]
                cleanup['reconciled_owned_uuid'] = uid
            if uid:
                require(before is not None and owns(uid,name,before,current),'Cleanup ownership uncertain')
                # Export the independently identified file while the owned container exists.
                # Its failure cannot widen cleanup or replace the original test outcome.
                if bundle.exists():
                    export = snapshot.export_owned_prefix(c,collector,uid,name,before,current)
                require(c.settled,'Unsettled export group; no simulator cleanup')
                if current[uid]['state'] != 'Shutdown':
                    c.run('cleanup-shutdown',['xcrun','simctl','shutdown',uid],60,final=True)
                c.run('cleanup-delete',['xcrun','simctl','delete',uid],60,final=True)
            after = flat(json.loads(c.run('cleanup-readback',['xcrun','simctl','list','devices','-j'],45,final=True)))
            save(evidence/'devices-after.json',after)
            cleanup['owned_deleted'] = uid is None or uid not in after
            cleanup['preexisting_stable'] = before is not None and stable(after) == stable(before)
            cleanup['metadata_differences'] = {k:{'before':before[k],'after':after.get(k)} for k in (before or {}) if before[k]!=after.get(k)}
            cleanup['verified'] = cleanup['owned_deleted'] and (cleanup['preexisting_stable'] or before is None and not attempted)
        except Exception as exc:
            cleanup['error'] = str(exc)
        save(evidence/'cleanup.json',cleanup)
        save(evidence/'snapshot-export-receipt.json',export)
        verdict = {'capture_valid':False,'capture_errors':['Result unavailable or extraction not completed']}
        if bundle.exists() and c.settled:
            try:
                verdict = collector.collect(uid,source_valid)
            except Exception as exc:
                verdict['capture_errors'] = [type(exc).__name__+': '+str(exc)]
        save(evidence/'collector-verdict.json',verdict)
        save(evidence/'qualified-interpretation.json',snapshot.interpret(export,verdict,status['raw_test_exit']))
        if lock_sha is not None and sha((repo/LOCK).read_bytes()) != lock_sha:
            status['cleanup_errors'].append('Dependency lock changed')
        status['finished_at'] = now()
        status['execution_elapsed_seconds'] = time.monotonic()-budget.started
        status['cleanup_verified'] = cleanup['verified']
        status['collector_valid'] = verdict['capture_valid']
        status['snapshot_valid'] = export.get('classification',{}).get('valid',False)
        status['actual_case_count'] = len(verdict['actual_cases']) if 'actual_cases' in verdict else None
        status['actual_execution_count'] = verdict.get('legacy_execution_count')
        save(evidence/'status.json',status)
        if status['primary_error'] or status['cleanup_errors'] or not cleanup['verified'] or not verdict['capture_valid'] or not status['snapshot_valid']:
            code = 1
        try:
            require(c.settled, 'Unresolved owned group; bundle may be mutating, no extraction/hash/upload eligibility')
            manifest(evidence,budget)
            (root/'upload-eligible').write_text('manifest complete\n')
        except Exception as exc:
            save(root/'artifact-blocker.json',{'error':str(exc)})
            code = 1
        for s, handler in old.items():
            signal.signal(s,handler)
    return code

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['execute','extract'])
    parser.add_argument('--bundle',type=Path)
    parser.add_argument('--output',type=Path)
    args = parser.parse_args()
    if args.mode == 'execute':
        require(args.bundle is None and args.output is None,'Execution paths are fixed by workflow')
        return execute(os.environ)
    require(args.bundle is not None and args.output is not None,'Offline extraction paths required')
    args.output.mkdir(exist_ok=False)
    c = Commands(args.output,Path.cwd(),os.environ.copy(),Budget(time.monotonic()))
    # Offline extraction intentionally does not invent approved source/device provenance.
    Collector(c,args.bundle.resolve(),args.output).collect()
    manifest(args.output,c.budget)
    return 0

if __name__ == '__main__':
    sys.exit(main())

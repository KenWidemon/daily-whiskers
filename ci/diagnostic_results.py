"""Selected-test diagnostic evidence, deliberately incompatible with CI Gate."""
import argparse
import json
import math
import os
from pathlib import Path
import subprocess
import time
import uuid

import diagnostic as d
import simulator
from results import test_counts

STATUS_FIELDS = {'enabled', 'authorization', 'storage_blocked', 'cleanup_pending', 'has_error'}
EVENT_FIELDS = {
    'session.start': set(),
    'binding.setter': STATUS_FIELDS | {'command', 'requested_enabled', 'busy', 'loaded'},
    **{name: STATUS_FIELDS | {'command', 'busy', 'loaded'} for name in
       ('model.command.enter', 'model.busy.published', 'model.status.published', 'model.command.complete')},
    'scheduler.command.enqueued': {'command'}, 'scheduler.command.enter': {'command'},
    'scheduler.command.result': STATUS_FIELDS | {'command'},
    'storage.persist.begin': {'enabled'}, 'storage.persist.verified': {'enabled'},
    'storage.persist.error': {'enabled', 'error_category'},
    'authorization.read.begin': {'command'}, 'authorization.read.complete': {'command', 'authorization'},
    'authorization.request.begin': {'command'}, 'authorization.request.complete': {'command'},
    'authorization.request.error': {'command', 'error_category'},
    'scheduler.state.begin': {'command'}, 'scheduler.state.ready': {'command', 'enabled'},
    'scheduler.enable.intent': {'command', 'enabled'},
    'scheduler.command.error': {'command', 'authorization', 'error_category'},
}


def validate_trace_event(event):
    d.require(isinstance(event, dict), 'Invalid trace event')
    name, fields = event.get('event'), event.get('fields')
    d.require(name in EVENT_FIELDS and isinstance(fields, dict)
              and all(isinstance(k, str) and isinstance(v, str) for k, v in fields.items()), 'Missing trace event schema')
    d.require(EVENT_FIELDS[name] <= fields.keys(), 'Missing fields for trace event ' + name)
    wall = event.get('wall_time_unix')
    d.require(type(wall) in (int, float) and math.isfinite(wall) and wall > 0, 'Missing event wall timestamp')
    command_id = event.get('command_id')
    if name != 'session.start':
        d.require(isinstance(command_id, str) and str(uuid.UUID(command_id)).upper() == command_id,
                  'Missing/invalid trace command identity')
    else:
        d.require(command_id is None and not fields, 'Malformed session-start event')
    allowed = STATUS_FIELDS | {'command', 'requested_enabled', 'busy', 'loaded', 'error_category'}
    d.require(fields.keys() <= allowed, 'Unknown trace field')
    for key in ('enabled', 'requested_enabled', 'storage_blocked', 'cleanup_pending', 'has_error', 'busy', 'loaded'):
        d.require(key not in fields or fields[key] in ('true', 'false'), 'Invalid boolean trace field')
    if 'command' in fields:
        d.require(fields['command'] in ('refresh', 'enable', 'time'), 'Unknown reminder command')
        d.require(fields['command'] != 'enable' or 'requested_enabled' in fields, 'Missing requested enabled state')
    d.require('authorization' not in fields or fields['authorization'] in ('notDetermined', 'denied', 'authorized', 'quiet'),
              'Unknown authorization state')
    d.require('error_category' not in fields or bool(fields['error_category']), 'Missing error category')


def selected_case(tree, selector):
    found = []
    def visit(nodes):
        d.require(isinstance(nodes, list), 'Invalid test tree')
        for node in nodes:
            if node.get('nodeType') == 'Test Case':
                found.append(node)
            visit(node.get('children', []))
    visit(tree['testNodes'])
    d.require(len(found) == 1, 'Missing/repeated/unplanned selected methods')
    node = found[0]
    target, case, method = selector.split('/')
    d.require(node.get('nodeIdentifier') == f'{case}/{method}()'
              and node.get('nodeIdentifierURL', '').endswith('/' + selector)
              and node.get('result') == 'Passed', 'Wrong, skipped, or failed selected method')
    return selector


def validate_selected(summary, tree, selector, identifier):
    counts = test_counts(summary)
    d.require(counts['valid_pass'] and counts['totalTestCount'] == counts['executions'] == 1,
              'Failed/skipped/repeated selected execution')
    devices = counts['devices']
    d.require(len(devices) == 1, 'Ambiguous observed destination')
    d.require(all(devices[0].get(key) == value for key, value in {
        'passedTests': 1, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}.items()),
        'Contradictory observed-device test counts')
    observed = devices[0]['device']
    for key, value in {'deviceName': simulator.NAME, 'modelName': simulator.NAME,
                       'osVersion': simulator.VERSION, 'osBuildNumber': simulator.BUILD,
                       'architecture': 'arm64', 'platform': 'iOS Simulator', 'deviceId': identifier}.items():
        d.require(observed.get(key) == value, 'Wrong/missing observed destination ' + key)
    return selected_case(tree, selector)


def verify_stage(record, name, current, deadline):
    d.require(record.get('stage') == name and record.get('status') == 'success'
              and record.get('exit_code') == 0, 'Incomplete/failed stage ' + name)
    d.require(all(record.get(key) == value for key, value in current.items()
                  if key not in ('lane', 'event_sha')), 'Cross-run/lane stage ' + name)
    if name != 'cleanup':
        d.require(record.get('deadline') == deadline, 'Changed execution budget in ' + name)
    d.require(not record.get('cleanup_errors') and not record.get('cleanup_reap_error'), 'Uncertain process cleanup')


def validate_launch(launch, stage, current, deadline):
    d.require(all(launch.get(k) == v for k, v in current.items()) and launch.get('stage') == stage
              and type(launch.get('pid')) is int and launch['pid'] > 0
              and launch.get('deadline') == deadline
              and launch.get('command') == d.test_command(current['lane'], stage),
              'Cross-run/missing PID or wrong managed destination launch')


def validate_result_invocation(summary, launch, stage):
    from diagnostic_postrun import finite_clock, validate_invocation
    exited = json.loads((d.DIAGNOSTIC / stage / 'exit.json').read_text())
    validate_invocation(launch, exited, stage)
    d.require(exited['exit_code'] == 0 and finite_clock(summary.get('startTime'))
              and finite_clock(summary.get('finishTime'))
              and launch['started'] <= summary['startTime'] <= summary['finishTime'] <= exited['finished'],
              'Finalized result outside exact successful invocation')


def validate_checkpoint(record, stage, current, deadline, identifier):
    d.require(all(record.get(k) == v for k, v in current.items()) and record.get('stage') == stage
              and record.get('status') == 'success' and record.get('exit_code') == 0 and record.get('errors') == {}
              and record.get('deadline') == deadline and record.get('simulator_id') == identifier,
              'Missing/failed/cross-run selected result checkpoint')
    d.require(record.get('product_test_passed') is True and record.get('postrun_evidence_complete') is True,
              'Incomplete product/post-run checkpoint')
    from diagnostic_postrun import verify_evidence
    d.require(record.get('postrun') == verify_evidence(stage, collect=True), 'Changed post-run evidence')
    validate_launch(record['launch'], stage, current, deadline)
    validate_result_invocation(record['summary'], record['launch'], stage)
    d.require(record['launch'] == json.loads((d.DIAGNOSTIC / stage / 'launch.json').read_text()),
              'Checkpoint differs from original launch record')
    return validate_selected(record['summary'], record['tree'], dict(d.LANES[current['lane']])[stage], identifier)


def checkpoint(stage, code):
    current = d.identity()
    record = dict(current, stage=stage, status='failure', exit_code=code, summary=None, tree=None, errors={},
                  product_test_passed=False, postrun_evidence_complete=False)
    path = d.DIAGNOSTIC / stage / 'verified-result.json'
    try:
        record.update(deadline=d.deadline(), simulator_id=d.owned()['simulator_id'])
        record['launch'] = json.loads((path.parent / 'launch.json').read_text())
        validate_launch(record['launch'], stage, current, record['deadline'])
        bundle = d.BUILD / f'Diagnostic-{stage}.xcresult'
        d.require((bundle / 'Info.plist').is_file(), 'No finalized selected result; raw Staging retained')
        # Preserve each reader independently if the other fails.
        for operation, key in (('summary', 'summary'), ('tests', 'tree')):
            try:
                raw = d.run_output(['xcrun', 'xcresulttool', 'get', 'test-results', operation,
                                    '--path', str(bundle)], seconds=20, until=record['deadline'])
                (path.parent / f'{operation}.json').write_text(raw + '\n')
                record[key] = json.loads(raw)
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                record['errors'][operation] = str(error)[:4096]
        d.require(code == 0 and not record['errors'], 'Selected command/readers failed')
        validate_selected(record['summary'], record['tree'], dict(d.LANES[current['lane']])[stage], record['simulator_id'])
        validate_result_invocation(record['summary'], record['launch'], stage)
        record['product_test_passed'] = True
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError) as error:
        record['errors']['verification'] = f'{type(error).__name__}: {error}'
    # Preserve independent diagnostic evidence even when the product test fails.
    try:
        from diagnostic_postrun import verify_evidence
        record['postrun'] = verify_evidence(stage)
        record['postrun_evidence_complete'] = True
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError) as error:
        record['errors']['postrun'] = f'{type(error).__name__}: {error}'
    try:
        d.deadline()  # No late evidence can unlock another method.
        if record['product_test_passed'] and record['postrun_evidence_complete'] and not record['errors']:
            record['status'] = 'success'
    except (OSError, ValueError, KeyError, TypeError) as error:
        record['errors']['deadline'] = f'{type(error).__name__}: {error}'
    d.write(path, record)
    d.require(record['status'] == 'success', 'Selected result checkpoint failed; next method blocked')
    return record


def verify_predecessor(lane, stage):
    stages = [name for name, _ in d.LANES[lane]]
    index = stages.index(stage)
    if index:
        previous = stages[index - 1]
        current, deadline = d.identity(), d.deadline()
        status = json.loads((d.BUILD / f'{previous}-status.json').read_text())
        record = json.loads((d.DIAGNOSTIC / previous / 'verified-result.json').read_text())
        verify_stage(status, previous, current, deadline)
        validate_checkpoint(record, previous, current, deadline, d.owned()['simulator_id'])


def validate_markers(paths, selector, monitor, metadata):
    from diagnostic_postrun import normalize_test_name, read_markers, valid_marker
    relevant = []
    method = selector.split('/')[-1]
    for path in paths:
        rows, complete = read_markers(path)
        if not rows or not normalize_test_name(rows[0].get('test', ''), selector):
            continue
        d.require(complete, 'Partial final marker line')
        d.require([row['sequence'] for row in rows] == list(range(1, len(rows) + 1)), 'Missing/repeated/out-of-order marker sequence')
        session = str(uuid.UUID(rows[0]['session_id'])).upper()
        d.require(rows[0]['session_id'] == session, 'Invalid marker session')
        fixed = ('session_id', 'pid', 'runner_bundle_id', 'container_home', 'test', 'stream', 'process_name')
        pending = set()
        previous_time = 0
        for row in rows:
            valid_marker(row, monitor['runner_pid'], metadata, monitor['stage'])
            d.require(all(row.get(key) == rows[0].get(key) for key in fixed), 'Mixed marker identity')
            d.require(row['container_home'] == monitor['runner_data_container'], 'Wrong marker container')
            event = int(row['event_monotonic_ns'])
            d.require(previous_time <= event <= int(row['export_monotonic_ns']), 'Invalid marker monotonic clock')
            previous_time = event
            if row['phase'] == 'app_termination':
                operation = row['operation_id']
                d.require(operation, 'Missing termination operation ID')
                if row['edge'] == 'enter':
                    d.require(operation not in pending, 'Repeated termination enter')
                    pending.add(operation)
                else:
                    d.require(row['edge'] == 'return' and operation in pending, 'Unpaired termination return')
                    pending.remove(operation)
        d.require(not pending, 'Outstanding termination at terminal marker')
        d.require(rows[0]['phase'] == 'test' and rows[0]['edge'] == 'enter', 'Missing initial test marker')
        terminal = [row for row in rows if row.get('phase') == 'test' and row.get('edge') == 'return']
        d.require(len(terminal) == 1 and terminal[0] == rows[-1] and terminal[0].get('stream_complete') is True
                  and terminal[0].get('terminal') is True, 'No complete final runner terminal marker')
        relevant.append({'path': str(path), 'events': len(rows), 'pid': rows[0]['pid'],
                         'session_id': rows[0]['session_id']})
    d.require(len(relevant) == 1, 'Missing/ambiguous selected marker session')
    return relevant[0]


def validate_trace(path, log_path):
    trace = json.loads(path.read_text())
    d.require(trace.get('schema_version') == 1 and trace.get('observation_scope') == 'initial_enable'
              and trace.get('export_complete') is True and trace.get('dropped_events') == 0
              and trace.get('export_failures') == 0 and not trace.get('last_export_error_category'),
              'Incomplete/overflowed reminder trace')
    session = str(uuid.UUID(trace['session_id'])).upper()
    d.require(trace['session_id'] == session and path.name == f'reminder-{session}.json', 'Mismatched trace session/file')
    events = trace['events']
    d.require(events and [event['sequence'] for event in events] == list(range(1, len(events) + 1))
              and trace['last_sequence'] == len(events) <= 1024, 'Missing/duplicate trace events')
    start, watermark = trace['capture_started_monotonic_ns'], trace['capture_complete_through_monotonic_ns']
    d.require(type(start) is int and type(watermark) is int and 0 < start <= watermark, 'Invalid trace bounds')
    last = start
    for event in events:
        validate_trace_event(event)
        stamp = event['monotonic_ns']
        d.require(type(stamp) is int and last <= stamp <= watermark, 'Out-of-order/out-of-watermark trace')
        last = stamp
    d.require(log_path.stat().st_size <= 64 * 1024 * 1024, 'UI diagnostic log exceeds limit')
    ui = []
    for line in log_path.read_text(errors='replace').splitlines():
        prefix = 'DW_REMINDER_UI_DIAGNOSTIC '
        if prefix in line:
            ui.append(json.loads(line.split(prefix, 1)[1]))
    d.require(ui and all(row.get('session_id') == session for row in ui), 'Missing/cross-session UI diagnostic')
    configured = [row for row in ui if row.get('event') == 'launch.configured']
    taps = [row for row in ui if row.get('event') == 'native_tap.return' and row.get('action_index') == 1]
    waits = [row for row in ui if row.get('event') == 'wait.return' and row.get('action_index') == 1 and row.get('expected') == '1']
    d.require(len(configured) == len(taps) == len(waits) == 1
              and configured[0].get('observation_scope') == 'initial_enable', 'Missing/ambiguous initial-enable window')
    tap, wait = taps[0], waits[0]
    d.require(start <= tap['tap_started_monotonic_ns'] <= tap['tap_returned_monotonic_ns']
              <= wait['wait_started_monotonic_ns'] <= wait['wait_returned_monotonic_ns'] <= watermark,
              'Trace watermark does not cover initial enable tap and original wait')
    # This certifies only the exported prefix. A process may die before a later
    # snapshot; absence after this watermark is never evidence of no callback.
    return {'path': str(path), 'coverage': 'initial-enable tap and wait only; not whole method',
            'session_id': session, 'initial_enable_wait': wait,
            'complete_through_monotonic_ns': trace['capture_complete_through_monotonic_ns'],
            'capture_closed': trace.get('capture_closed', False), 'events': len(trace.get('events', []))}


def collect():
    until = time.time() + 100
    current = d.identity()
    lane = current['lane']
    output = dict(schema='selected-diagnostic-v1', identity=current, acceptance=False,
                  scope='Selected diagnostic only; cannot satisfy 27-test acceptance or CI Gate',
                  launch_strategy='xcodebuild-managed', evidence_mode='post-run-only',
                  live_diagnostics='not requested; no live stall evidence or startup cutoff',
                  cache='diagnostic uncached; not a certified cold control', stages={}, tests={}, errors={},
                  diagnostic_evidence_complete=False, selected_tests_passed=False)
    def capture(key, function):
        try:
            return function()
        except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError) as error:
            output['errors'][key] = {'type': type(error).__name__, 'message': str(error)[:4096],
                                     'output': str(getattr(error, 'output', ''))[:4096]}
            return None
    def read(path):
        return json.loads(path.read_text())
    stage_names = ['prepare', 'diagnostic-preflight', 'resolve', 'diagnostic-build',
                   *[name for name, _ in d.LANES[lane]], 'cleanup']
    for name in stage_names:
        output['stages'][name] = capture('stage.' + name, lambda name=name: read(d.BUILD / f'{name}-status.json'))
    output['budget'] = capture('budget', d.budget)
    output['simulator'] = capture('simulator', d.owned)
    output['preflight'] = capture('preflight', lambda: read(d.DIAGNOSTIC / 'preflight.json'))
    output['export'] = capture('export', lambda: read(d.DIAGNOSTIC / 'export.json'))
    output['metadata'] = capture('metadata', lambda: read(d.DIAGNOSTIC / 'built-metadata.json'))
    for stage, selector in d.LANES[lane]:
        result = output['tests'][stage] = {'planned': selector, 'summary': None, 'tree': None}
        bundle = d.BUILD / f'Diagnostic-{stage}.xcresult'
        result['bundle_exists'] = bundle.exists()
        result['info_plist_exists'] = (bundle / 'Info.plist').exists()
        for operation in ('summary', 'tests'):
            def read_result(operation=operation):
                raw = d.run_output(['xcrun', 'xcresulttool', 'get', 'test-results', operation,
                                    '--path', str(bundle)], seconds=20, until=until)
                (d.DIAGNOSTIC / f'{stage}-{operation}.json').write_text(raw + '\n')
                return json.loads(raw)
            value = capture(f'{stage}.{operation}', read_result)
            result['summary' if operation == 'summary' else 'tree'] = value
        result['launch'] = capture(stage + '.launch', lambda stage=stage: read(d.DIAGNOSTIC / stage / 'launch.json'))
        result['checkpoint'] = capture(stage + '.checkpoint', lambda stage=stage: read(d.DIAGNOSTIC / stage / 'verified-result.json'))
        if lane != 'visual':
            result['postrun'] = capture(stage + '.postrun', lambda stage=stage: read(d.DIAGNOSTIC / stage / 'postrun.json'))
    def verify():
        budget = output['budget']
        d.require(budget['execution_seconds'] == 2700 and budget['deadline'] - budget['started'] == 2700,
                  'Changed original budget')
        for key, value in current.items():
            if key in ('source_sha', 'run_id', 'run_attempt', 'job', 'shard'):
                d.require(budget.get(key) == value, 'Cross-run budget')
        prep = output['simulator']
        d.require(all(prep.get(k) == v for k, v in simulator.identity().items()), 'Cross-run simulator')
        identifier = simulator.valid_uuid(prep['simulator_id'])
        d.require(prep.get('ownership') == 'created' and identifier not in prep['preexisting_ids']
                  and prep['readback_verified'] is True and prep['status'] == 'ready', 'Unverified ownership')
        cleanup = output['stages']['cleanup']
        d.require(cleanup.get('operation') == 'delete-owned' and cleanup.get('simulator_id') == identifier
                  and cleanup.get('readback_verified') is True, 'Missing cleanup readback')
        d.require(output['preflight']['status'] == 'success' and output['preflight']['cache_restore'] == 'disabled'
                  and output['preflight']['cache_save'] == 'disabled', 'Missing diagnostic preflight')
        for component in ('preflight', 'export', 'metadata'):
            d.require(all(output[component].get(k) == v for k, v in current.items()), 'Cross-run ' + component)
        d.require(output['export']['status'] == 'complete' and not output['export']['errors'], 'Incomplete final export')
        simulator.verify_toolchain((d.BUILD / 'toolchain.txt').read_text())
    capture('provenance', verify)
    # Validate independent evidence even when the target assertion fails. A
    # failed test is the diagnostic's subject, not a reason to discard its trace.
    for name, record in output['stages'].items():
        capture('validate.stage.' + name, lambda name=name, record=record:
                verify_stage(record, name, current, output['budget']['deadline']))
    for stage, selector in d.LANES[lane]:
        result = output['tests'][stage]
        result['verified_selected_method'] = capture('validate.selected.' + stage,
            lambda result=result, selector=selector: validate_selected(
                result['summary'], result['tree'], selector, output['simulator']['simulator_id']))
        capture('validate.launch.' + stage, lambda result=result, stage=stage:
                validate_launch(result['launch'], stage, current, output['budget']['deadline']))
        def product_identity(result=result, stage=stage):
            validate_result_invocation(result['summary'], result['launch'], stage)
            d.require(result['info_plist_exists'], 'Unfinalized result bundle')
            return True
        result['product_invocation_verified'] = capture('validate.product_invocation.' + stage, product_identity)
        result['verified_checkpoint_method'] = capture('validate.checkpoint.' + stage, lambda result=result, stage=stage:
                validate_checkpoint(result['checkpoint'], stage, current, output['budget']['deadline'],
                                    output['simulator']['simulator_id']))
        if lane != 'visual':
            from diagnostic_postrun import verify_evidence
            result['postrun_evidence'] = capture('validate.postrun.' + stage,
                lambda stage=stage: verify_evidence(stage, collect=True))
    # A diagnostic export failure does not relabel a passing product assertion.
    output['selected_tests_passed'] = all(result['verified_selected_method']
        and 'validate.launch.' + stage not in output['errors']
        and result['product_invocation_verified']
        for stage, result in output['tests'].items())
    output['diagnostic_evidence_complete'] = not output['errors']
    d.write(d.DIAGNOSTIC / 'results.json', output)
    return output


def render(output):
    current = output.get('identity', {})
    lines = ['## DIAGNOSTIC ONLY: ' + str(current.get('lane', 'unknown')),
             'Not CI Gate, not full 27-test acceptance, not release acceptance.',
             'Cache explicitly disabled: diagnostic uncached, not a certified cold control.',
             f"Source/checkout: {current.get('source_sha')} / {current.get('tested_sha')}",
             f"Run/attempt/lane: {current.get('run_id')} / {current.get('run_attempt')} / {current.get('lane')}",
             f"Selected tests passing: {output.get('selected_tests_passed', False)}; "
             f"diagnostic evidence complete: {output.get('diagnostic_evidence_complete', False)}."]
    for stage, record in output.get('stages', {}).items():
        lines.append(f"- {stage}: {(record or {}).get('status', 'not run / unavailable')}")
    for key, error in output.get('errors', {}).items():
        lines.append(f"- Inconclusive {key}: {error.get('message', 'unavailable')}")
    lines += ['Missing/partial/late/overflowed traces cannot prove absence or causality. '
              'Live diagnostics were not requested: no live stall evidence or 300-second startup cutoff. Raw videos/screenshots and unfinished '
              'xcresult Staging are retained. I/O contention is a hypothesis, not an established cause.']
    if os.environ.get('ARTIFACT_URL'):
        lines.append(f"[Raw diagnostic evidence]({os.environ['ARTIFACT_URL']}) (30-day retention).")
    return '\n\n'.join(lines) + '\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=('collect', 'render'))
    args = parser.parse_args()
    if args.command == 'collect':
        data = collect()
        raise SystemExit(0 if data['diagnostic_evidence_complete'] else 1)
    path = d.DIAGNOSTIC / 'results.json'
    data = json.loads(path.read_text()) if path.exists() else {'errors': {'collection': {'message': 'Collection unavailable'}}}
    text = render(data)
    print(text)
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
        summary.write(text)

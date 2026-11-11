"""Bound optional cache restore by the existing job deadline, never renew it."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import sys
import time

STARTUP_SLACK_SECONDS = 60
MAX_RESTORE_MINUTES = 5
EXECUTION_SECONDS = 2700
IDENTITY = {'source_sha': 'SOURCE_SHA', 'run_id': 'GITHUB_RUN_ID',
            'run_attempt': 'GITHUB_RUN_ATTEMPT', 'job': 'GITHUB_JOB', 'shard': 'CI_SHARD_ID'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def window(budget, env, now):
    """Pure selection function. None means skip, not a zero/unlimited timeout."""
    require(isinstance(budget, dict), 'Malformed execution budget object')
    expected = {key: env.get(variable, '') for key, variable in IDENTITY.items()}
    require(all(isinstance(v, str) and v for v in expected.values()), 'Missing budget identity')
    require(re.fullmatch(r'[0-9a-f]{40}', expected['source_sha']) is not None, 'Invalid source SHA')
    require(all(re.fullmatch(r'[1-9][0-9]*', expected[k]) for k in ('run_id', 'run_attempt')), 'Invalid run/attempt')
    part = env.get('CI_PART')
    require(part in ('unit-release', 'cards', 'settings', 'reminders') and expected['shard'] == part,
            'Invalid cache shard identity')
    require(expected['job'] == ('build-and-test' if part == 'unit-release' else 'ui-shards'), 'Invalid cache job identity')
    require(all(budget.get(k) == v for k, v in expected.items()), 'Stale or wrong-identity execution budget')
    tested = env.get('TESTED_SHA', '')
    require(re.fullmatch(r'[0-9a-f]{40}', tested) is not None, 'Missing/invalid tested checkout SHA')
    start, duration, deadline = (budget.get(k) for k in ('started', 'execution_seconds', 'deadline'))
    require(all(finite(value) for value in (start, duration, deadline, now)), 'Non-finite/malformed execution budget')
    require(start > 0 and start <= now and duration == EXECUTION_SECONDS and deadline == start + duration,
            'Invalid execution budget duration/timestamps')
    exported = float(env.get('CI_EXECUTION_DEADLINE', ''))
    require(math.isfinite(exported) and exported == deadline, 'Missing/mismatched exported execution deadline')
    remaining = deadline - now
    minutes = min(MAX_RESTORE_MINUTES, math.floor((remaining - STARTUP_SLACK_SECONDS) / 60))
    return dict(expected, schema=1, stage='cache', tested_sha=tested, started=start,
                execution_seconds=duration, deadline=deadline, planned_at=now,
                startup_slack_seconds=STARTUP_SLACK_SECONDS,
                decision='restore' if minutes >= 1 else 'skip_insufficient_budget',
                timeout_minutes=minutes if minutes >= 1 else None)


def classify(record, observation, reported_at):
    require(finite(reported_at) and reported_at >= record['planned_at'], 'Invalid cache observation time')
    outcome, hit, primary, matched = (observation[k] for k in ('outcome', 'cache_hit', 'primary_key', 'matched_key'))
    require(all(isinstance(value, str) for value in (outcome, hit, primary, matched)), 'Invalid cache observation')
    if record['decision'] == 'skip_insufficient_budget':
        require(outcome == 'skipped' and hit == primary == matched == '', 'Unexpected restore after budget skip')
        return 'skipped_budget'
    require(outcome == 'success', f'Cache restore did not complete successfully: {outcome or "unavailable"}')
    require(reported_at <= record['deadline'], 'Cache restore/report exceeded the shared execution deadline')
    require(primary and hit in ('true', 'false', ''), 'Incomplete cache action outputs')
    if hit == 'true':
        require(matched == primary, 'Exact cache hit lacks matching key evidence')
        return 'exact_hit'
    if matched:
        require(matched != primary, 'Inconsistent cache hit/key evidence')
        return 'partial_restore'
    return 'cold_miss'


def verify_record(record, current, part, budget):
    """Verify optional-cache provenance without requiring a cache hit or restore."""
    env = dict(current, CI_PART=part, CI_SHARD_ID=part,
               GITHUB_JOB='build-and-test' if part == 'unit-release' else 'ui-shards',
               CI_EXECUTION_DEADLINE=str(budget['deadline']))
    planned = window(budget, env, record['planned_at'])
    require(all(record.get(k) == v for k, v in planned.items()), 'Inconsistent cache window evidence')
    require(record.get('status') == 'success' and record.get('classification') ==
            classify(record, record['observation'], record['reported_at']), 'Incomplete/invalid cache evidence')


def write(path, record):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(record, indent=2) + '\n')
    temporary.replace(path)


def execute(command, directory, env, now):
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / 'cache-status.json'
    record = {'stage': 'cache', 'status': 'failure', 'classification': 'unavailable'}
    try:
        budget = json.loads((directory / 'job-budget.json').read_text())
        if command == 'plan':
            require(not path.exists(), 'Cache window must be selected only once')
            record = window(budget, env, now) | {'status': 'planned'}
            write(path, record)
            with open(env['GITHUB_OUTPUT'], 'a') as output:
                # The skipped branch exports an inert finite guard, never zero.
                output.write(f"restore={'true' if record['decision'] == 'restore' else 'false'}\n")
                output.write(f"timeout_minutes={record['timeout_minutes'] or 1}\n")
        else:
            stored = json.loads(path.read_text())
            require(isinstance(stored, dict), 'Malformed cache window object')
            record = stored
            planned = window(budget, env, record['planned_at'])
            require(record.get('status') == 'planned' and all(record.get(k) == v for k, v in planned.items()),
                    'Missing/stale/changed cache window')
            record.update(reported_at=now, observation={
                'outcome': env.get('CACHE_OUTCOME', ''), 'cache_hit': env.get('CACHE_HIT', ''),
                'primary_key': env.get('CACHE_PRIMARY_KEY', ''), 'matched_key': env.get('CACHE_MATCHED_KEY', '')})
            record['classification'] = classify(record, record['observation'], now)
            record['status'] = 'success'
    except (OSError, ValueError, KeyError, TypeError) as error:
        record.update(status='failure', classification='unavailable', error=f'{type(error).__name__}: {error}')
    write(path, record)
    if command == 'report':
        message = (f"SwiftPM cache: {record.get('classification', 'unavailable')}; "
                   f"decision={record.get('decision', 'unavailable')}; "
                   f"restore timeout={record.get('timeout_minutes')} minutes; "
                   f"status={record['status']}. Skipped/failed/partial restore is neither a warm hit nor a cold miss.")
        if record.get('error'):
            message += ' ' + record['error']
        print(message)
        with open(env['GITHUB_STEP_SUMMARY'], 'a') as output:
            output.write(message + '\n')
    return 1 if record['status'] == 'failure' else 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=('plan', 'report'))
    parser.add_argument('--directory', type=Path, default=Path('build'))
    args = parser.parse_args()
    sys.exit(execute(args.command, args.directory, os.environ, time.time()))

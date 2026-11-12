"""Disposable selected-test diagnostic. Never produces acceptance evidence.

No simulator or process operations occur on import. Hosted operations require
the original run-stage budget and exact owned simulator preparation record.
"""
import argparse
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

import simulator

LANES = {
    'visual': [('visual', 'DailyWhiskersTests/DailyCardShareVisualTests/testAdaptiveViewportRetainsArtworkScaleAndNaturalScrollingHeight')],
    'startup-reminder': [
        ('startup', 'DailyWhiskersUITests/RegressionSmokeTests/testAccountToolsOpenAndDismiss'),
        ('reminder', 'DailyWhiskersUITests/ReminderUITests/testPermissionRevocationRegrantAndExplicitDisable')],
    'cards': [
        ('cards-largest', 'DailyWhiskersUITests/SavedCardsTests/testLargestTextLandscapeSavedCardActionsAndVibe'),
        ('cards-adaptive', 'DailyWhiskersUITests/SavedCardsTests/testAdaptiveCardAndSavedTilesAcrossWindowSizes')],
}
BUILD = Path('build')
DIAGNOSTIC = BUILD / 'diagnostic'
DERIVED = BUILD / 'DiagnosticDerivedData'
LOCK = Path('DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
require = simulator.require


def identity():
    result = simulator.identity() | {'lane': os.environ.get('CI_DIAGNOSTIC_LANE'),
                                     'event_sha': os.environ.get('GITHUB_SHA')}
    require(all(result.values()), 'Missing diagnostic identity')
    require(result['lane'] in LANES and result['shard'] == result['lane'], 'Unknown/mismatched lane')
    require(result['job'] == 'diagnostic', 'Not a diagnostic job')
    require(result['source_sha'] == result['tested_sha'] == result['event_sha'], 'Checkout/source mismatch')
    require(re.fullmatch('[0-9a-f]{40}', result['source_sha']) is not None, 'Invalid source SHA')
    require(re.fullmatch('[1-9][0-9]*', result['run_id']) and result['run_attempt'] == '1',
            'Invalid run/attempt identity')
    return result


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    simulator.write(path, value)


def budget():
    record = json.loads((BUILD / 'job-budget.json').read_text())
    current = identity()
    value = float(os.environ['CI_EXECUTION_DEADLINE'])
    require(math.isfinite(value) and record['deadline'] == value and record['execution_seconds'] == 2700
            and record['deadline'] - record['started'] == 2700, 'Missing/changed original diagnostic budget')
    require(all(record.get(key) == current[key] for key in ('source_sha', 'run_id', 'run_attempt', 'job', 'shard')),
            'Cross-run diagnostic budget')
    return record


def deadline():
    value = budget()['deadline']
    require(value > time.time(), 'Diagnostic execution budget exhausted')
    return value


def run_output(args, seconds=10, *, until=None):
    limit = min(seconds, (until if until is not None else deadline()) - time.time())
    require(limit > 0, 'Command budget exhausted')
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=limit).strip()


def owned():
    record = json.loads((BUILD / 'simulator.json').read_text())
    expected = simulator.identity()
    require(all(record.get(k) == v for k, v in expected.items()), 'Stale simulator ownership record')
    require(record.get('status') == 'ready' and record.get('readback_verified') is True
            and record.get('ownership') == 'created', 'Diagnostic requires a verified newly owned simulator')
    identifier = simulator.valid_uuid(record['simulator_id'])
    require(identifier == os.environ.get('SIMULATOR_ID') and identifier not in record['preexisting_ids'],
            'Unowned/mismatched simulator')
    for key, value in {'runtime': simulator.RUNTIME, 'version': simulator.VERSION, 'build': simulator.BUILD,
                       'architecture': 'arm64', 'name': simulator.NAME, 'device_type': simulator.DEVICE_TYPE}.items():
        require(record.get(key) == value, 'Wrong simulator ' + key)
    return record


def common():
    return ['-project', 'DailyWhiskers.xcodeproj', '-clonedSourcePackagesDirPath',
            str(Path(os.environ['GITHUB_WORKSPACE']) / 'build/SourcePackages'),
            '-onlyUsePackageVersionsFromResolvedFile', '-disableAutomaticPackageResolution', 'CODE_SIGNING_ALLOWED=NO']


def test_options(lane):
    options = [*common(), '-scheme', 'DailyWhiskers' if lane == 'visual' else 'DailyWhiskersInteraction',
            '-configuration', 'Debug',
            '-destination', f"platform=iOS Simulator,id={owned()['simulator_id']},arch=arm64",
            '-derivedDataPath', str(DERIVED), '-parallel-testing-enabled', 'NO']
    if lane != 'visual':
        options += ['SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING CI_DIAGNOSTIC_TESTING',
            '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '720',
            '-maximum-test-execution-time-allowance', '720']
    return options


def test_command(lane, stage):
    require(stage in dict(LANES[lane]), 'Unexpected selected test stage')
    return ['xcodebuild', 'test-without-building', *test_options(lane),
            '-only-testing:' + dict(LANES[lane])[stage],
            '-resultBundlePath', f'build/Diagnostic-{stage}.xcresult']


def test(lane, stage):
    from diagnostic_postrun import execute
    from diagnostic_results import checkpoint, verify_predecessor
    command = test_command(lane, stage)
    verify_predecessor(lane, stage)
    require(not (BUILD / f'Diagnostic-{stage}.xcresult').exists()
            and not (DIAGNOSTIC / stage / 'launch.json').exists()
            and not (DIAGNOSTIC / stage / 'verified-result.json').exists(), 'Selected method must run only once')
    check_lock()
    code = execute(command, lane, stage)
    check_lock()
    # Even an exit-zero command cannot unlock the next method without actual
    # xcresult method/count/device evidence, inside the unchanged lane deadline.
    checkpoint(stage, code)
    return code


def check_lock():
    require(LOCK.read_bytes() == (Path(os.environ['RUNNER_TEMP']) / 'Package.resolved.expected').read_bytes(),
            'Dependency lock changed during diagnostic')


def metadata(lane):
    products = DERIVED / 'Build/Products/Debug-iphonesimulator'
    candidates = [products / 'DailyWhiskers.app']
    if lane != 'visual':
        runners = list(products.glob('*-Runner.app'))
        require(len(runners) == 1, 'Missing/ambiguous built UI runner')
        candidates += runners
    output = dict(identity(), bundles={})
    for kind, path in zip(('app', 'runner'), candidates):
        with (path / 'Info.plist').open('rb') as source:
            data = plistlib.load(source)
        bundle_id, executable = data.get('CFBundleIdentifier'), data.get('CFBundleExecutable')
        require(isinstance(bundle_id, str) and bundle_id and isinstance(executable, str)
                and Path(executable).name == executable and (path / executable).is_file(), 'Invalid built bundle metadata')
        from diagnostic_postrun import digest
        binaries = {str(file.relative_to(path)): digest(file) for file in path.rglob('*')
                    if file.is_file() and (file.name == executable or file.suffix == '.dylib' or file.parent.suffix == '.xctest'
                                           and file.name == file.parent.stem)}
        require(kind != 'runner' or any(Path(name).parent.suffix == '.xctest'
                and Path(name).name == Path(name).parent.stem for name in binaries), 'Missing built UI test executable')
        output['bundles'][kind] = {'bundle_id': bundle_id, 'executable': executable,
                                  'built_path': str(path.resolve()), 'binaries': binaries}
    write(DIAGNOSTIC / 'built-metadata.json', output)
    return output


def preflight():
    current = identity()
    require(os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
            and os.environ.get('GITHUB_REF') == 'refs/heads/codex/ci-managed-launch-20261111'
            and os.environ.get('GITHUB_RUN_ATTEMPT') == '1', 'Only one initial disposable-branch dispatch is permitted')
    deadline()
    owned()
    require(not (BUILD / 'SourcePackages').exists(), 'Uncached diagnostic starts with unexpected dependency directory')
    from diagnostic_postrun import MARKER_CLOCK_DOMAIN, marker_uptime_ns
    stamp = marker_uptime_ns()
    write(DIAGNOSTIC / 'preflight.json', dict(current, status='success',
          monotonic_clock_domain=MARKER_CLOCK_DOMAIN, host_uptime_probe_ns=stamp,
          evidence_mode='post-run-only', live_diagnostics='not requested', startup_cutoff_seconds=None,
          cache='diagnostic uncached', cache_restore='disabled', cache_save='disabled',
          cold_control_certified=False))


def build(lane):
    check_lock()
    code = subprocess.call(['xcodebuild', 'build-for-testing', *test_options(lane),
                            '-resultBundlePath', f'build/Diagnostic-{lane}-build.xcresult'])
    check_lock()
    if code == 0:
        metadata(lane)
    return code


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=('preflight', 'build', 'test', 'export'))
    parser.add_argument('--stage')
    args = parser.parse_args()
    DIAGNOSTIC.mkdir(parents=True, exist_ok=True)
    lane = identity()['lane']
    if args.command == 'preflight':
        preflight()
    elif args.command == 'build':
        return build(lane)
    elif args.command == 'test':
        return test(lane, args.stage)
    else:
        from diagnostic_postrun import export_all
        return export_all()
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f'::error::Diagnostic failed closed: {type(error).__name__}: {error}', file=sys.stderr)
        sys.exit(1)

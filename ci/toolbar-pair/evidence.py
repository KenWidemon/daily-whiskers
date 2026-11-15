"""Read-only receipts for one focused comparison, never a release gate."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

BASE = '79ad54a19b398a8222e86f116a5e939b7f009553'
METHOD = 'SavedCardsTests/testLargestTextPairedGeometryAndOptions()'
FILES = {
    'DailyWhiskers/Views/CardNavigationToolbar.swift': 'ed6f944bdbb73c967e19f44f22af0a238dd853570cc8420fe19a74ea63e7745b',
    'DailyWhiskersTests/CardNavigationToolbarTests.swift': 'b0b497261b4c1df33ee8bc14b43af5bd6ca3b0f8bf07131970d3b3f0814224f4',
    'DailyWhiskers.xcodeproj/project.pbxproj': 'c67ea84d9ba3424037ee594fe54272c4387fcf306a2c6ee9f75e34747bd9b40a',
}
HARNESS = {'.github/workflows/ios.yml', 'ci/toolbar-pair/run.sh',
           'ci/toolbar-pair/evidence.py', 'ci/toolbar-pair/test_evidence.py'}
LOCK = 'DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def git(*args):
    return subprocess.check_output(['git', *args], text=True, timeout=30).strip()


def write(name, data):
    Path('build').mkdir(exist_ok=True)
    Path('build', name).write_text(json.dumps(data, indent=2) + '\n')


def provenance():
    arm = os.environ['ARM']
    require(arm in ('control', 'treatment'), 'Unknown arm')
    require(os.environ['GITHUB_EVENT_NAME'] == 'workflow_dispatch', 'Manual run only')
    require(os.environ['GITHUB_REPOSITORY'] == 'KenWidemon/daily-whiskers', 'Wrong repository')
    require(os.environ['GITHUB_RUN_ATTEMPT'] == '1', 'No retry of this comparison')
    require(os.environ['GITHUB_REF'] == 'refs/heads/codex/pr143-toolbar-pair-design', 'Wrong experiment branch')
    head = git('rev-parse', 'HEAD')
    require(head == (BASE if arm == 'control' else os.environ['GITHUB_SHA']), 'Wrong source checkout')
    # Both arms verify the same reviewed treatment before spending test time.
    harness = Path('../harness')
    require(git('-C', str(harness), 'rev-parse', 'HEAD') == os.environ['GITHUB_SHA'], 'Wrong harness checkout')
    changed = set(git('-C', str(harness), 'diff', '--name-only', BASE, 'HEAD').splitlines())
    require(set(FILES) <= changed <= set(FILES) | HARNESS, 'Unexpected candidate changes')
    for path, expected in FILES.items():
        require(hashlib.sha256((harness / path).read_bytes()).hexdigest() == expected, 'Unreviewed candidate: ' + path)
    require(not git('status', '--porcelain'), 'Source checkout is dirty')
    require(not Path('build/SourcePackages').exists(), 'Expected fresh package directory')
    image = {key: os.environ.get(key) for key in ('ImageOS', 'ImageVersion', 'RUNNER_ARCH', 'RUNNER_OS')}
    require(all(image.values()), 'Missing runner image identity')
    write('toolbar-provenance.json', dict(arm=arm, source=head, workflow=os.environ['GITHUB_SHA'],
        run=os.environ['GITHUB_RUN_ID'], attempt=os.environ['GITHUB_RUN_ATTEMPT'],
        image=image, cache='disabled-fresh-package-directory', lock_sha256=hashlib.sha256(Path(LOCK).read_bytes()).hexdigest()))


def cases(tree):
    found = []
    def visit(nodes):
        for node in nodes:
            if node.get('nodeType') == 'Test Case':
                require(node.get('nodeIdentifierURL', '').endswith('/DailyWhiskersUITests/' + METHOD[:-2]), 'Wrong test target')
                found.append((node.get('nodeIdentifier'), node.get('result')))
            visit(node.get('children', []))
    visit(tree['testNodes'])
    require(len(found) == 1 and found[0][0] == METHOD, 'Wrong/missing/duplicate method')
    require(found[0][1] in ('Passed', 'Failed'), 'Skipped or unknown result')
    return found[0][1]


def validate_counts(counts, method_result):
    passed = method_result == 'Passed'
    require(method_result in ('Passed', 'Failed'), 'Unknown method result')
    require(counts['totalTestCount'] == 1 and counts['executions'] == 1
            and counts['skippedTests'] == counts['expectedFailures'] == 0,
            'Invalid focused counts')
    require(counts['passedTests'] == int(passed) and counts['failedTests'] == int(not passed)
            and counts['result'] == method_result and counts['valid_pass'] == passed,
            'Counts/tree disagreement')


def validate(data, environment, lock_hash):
    expected = dict(source_sha=environment['SOURCE_SHA'], tested_sha=environment['TESTED_SHA'],
                    run_id=environment['GITHUB_RUN_ID'], run_attempt=environment['GITHUB_RUN_ATTEMPT'],
                    job=environment['GITHUB_JOB'], shard=environment['CI_SHARD_ID'])
    provenance = data['toolbar-provenance']
    require(provenance['arm'] == environment['ARM'] and provenance['source'] == environment['SOURCE_SHA']
            and provenance['workflow'] == environment['GITHUB_SHA'] and provenance['run'] == environment['GITHUB_RUN_ID']
            and provenance['attempt'] == environment['GITHUB_RUN_ATTEMPT'], 'Stale provenance')
    require(provenance['cache'] == 'disabled-fresh-package-directory', 'Unexpected cache policy')
    require(all(provenance['image'].get(k) for k in ('ImageOS', 'ImageVersion', 'RUNNER_ARCH', 'RUNNER_OS')), 'Missing image identity')
    budget = data['job-budget']
    require(0 < budget['execution_seconds'] <= 2700 and abs(budget['deadline'] - float(environment['PAIR_DEADLINE'])) < 1,
            'Execution allowance changed')
    require(all(budget.get(k) == v for k, v in expected.items() if k != 'tested_sha'), 'Stale budget identity')
    for name in ('prepare', 'resolve', 'ui'):
        stage = data[name + '-status']
        require(all(stage.get(k) == v for k, v in expected.items()), 'Stale stage identity')
        require(stage.get('deadline') == data['job-budget']['deadline'], 'Deadline mismatch')
        require(not any(stage.get(k) for k in ('error', 'cleanup_errors', 'cleanup_reap_error', 'forced_kill', 'termination_signal')),
                'Interrupted or uncertain process cleanup')
        if name != 'ui':
            require(stage.get('status') == 'success' and stage.get('exit_code') == 0, 'Setup failed')
        else:
            require(stage.get('status') == ('success' if data['method_result'] == 'Passed' else 'failure'), 'Invalid UI stage status')
            expected_exit = 0 if data['method_result'] == 'Passed' else 65
            require(stage.get('exit_code') == stage.get('command_exit_code') == expected_exit,
                    'Test interrupted or process outcome disagreement')
    simulator = data['simulator']
    cleanup = data['cleanup-status']
    require(all(simulator.get(k) == v and cleanup.get(k) == v for k, v in expected.items()), 'Stale simulator identity')
    require(simulator.get('status') == 'ready' and simulator.get('readback_verified') is True, 'Simulator not ready')
    require(cleanup.get('status') == 'success' and cleanup.get('readback_verified') is True,
            'Unverified cleanup')
    require(cleanup.get('simulator_id') == simulator.get('simulator_id') ==
            data['counts']['devices'][0]['device'].get('deviceId'), 'Wrong simulator')
    require(cleanup.get('ownership') == simulator.get('ownership') == 'created'
            and cleanup.get('operation') == 'delete-owned', 'Unexpected simulator ownership')
    require(lock_hash == data['toolbar-provenance']['lock_sha256'], 'Changed dependency lock')


def collect():
    # Import the unchanged source's established readers and destination validator.
    sys.path.insert(0, str(Path('ci').resolve()))
    from results import read_xcresult, test_counts
    from ui_shards import device_environment
    from simulator import verify_toolchain
    data = {'comparison_eligible': False, 'acceptance_qualified': False}
    errors = []
    for name in ('toolbar-provenance', 'job-budget', 'prepare-status', 'resolve-status', 'ui-status', 'simulator', 'cleanup-status'):
        try:
            data[name] = json.loads(Path('build', name + '.json').read_text())
        except (OSError, ValueError) as error:
            errors.append(name + ': ' + str(error))
    try:
        data['toolchain'] = Path('build/toolchain.txt').read_text()
        verify_toolchain(data['toolchain'])
        summary = read_xcresult(Path('build'), 'ToolbarPair.xcresult', 'summary', 'toolbar-summary.json')
        tree = read_xcresult(Path('build'), 'ToolbarPair.xcresult', 'tests', 'toolbar-tests.json')
        data['counts'] = test_counts(summary)
        data['method_result'] = cases(tree)
        data['device'] = device_environment(data['counts'])
        validate_counts(data['counts'], data['method_result'])
        validate(data, os.environ, hashlib.sha256(Path(LOCK).read_bytes()).hexdigest())
    except (OSError, ValueError, KeyError, TypeError, IndexError, AttributeError, subprocess.SubprocessError) as error:
        errors.append(str(error))
    data['errors'] = errors
    data['comparison_eligible'] = not errors
    write('toolbar-result.json', data)
    print(json.dumps(data, indent=2))
    # Eligibility is only one arm; human review must compare image/device/cache,
    # then distinguish assertion reproduction from other test failures.
    return 0 if not errors else 1


if __name__ == '__main__':
    if sys.argv[1:] == ['provenance']:
        provenance()
    elif sys.argv[1:] == ['collect']:
        sys.exit(collect())
    else:
        raise SystemExit('Expected provenance or collect')

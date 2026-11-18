"""Reviewed UI inventory and fail-closed, same-run evidence aggregation."""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
SHARDS = ('cards', 'settings', 'reminders')
PARTS = ('unit-release', *SHARDS)
IDENTITY_KEYS = ('SOURCE_SHA', 'TESTED_SHA', 'GITHUB_SHA', 'GITHUB_RUN_ID',
                 'GITHUB_RUN_ATTEMPT', 'GITHUB_REPOSITORY')
DEVICE_KEYS = ('deviceName', 'modelName', 'osVersion', 'osBuildNumber', 'architecture', 'platform')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def inventory(root=ROOT):
    data = json.loads((root / 'ci/ui-inventory.json').read_text())
    require(data.get('schema') == 1 and set(data['shards']) == set(SHARDS), 'Unknown inventory/shards')
    discovered = {}
    for path in sorted((root / 'DailyWhiskersUITests').rglob('*.swift')):
        # This inventory deliberately supports the repository's final XCTestCase
        # classes. New classes/methods require a reviewed inventory update.
        chunks = re.split(r'\bfinal class (\w+): XCTestCase\s*\{', path.read_text())
        require(not re.search(r'\bfunc test\w+\s*\(', chunks[0]), 'Unassigned test method')
        for name, body in zip(chunks[1::2], chunks[2::2]):
            methods = re.findall(r'\bfunc (test\w+)\s*\(', body)
            require(name not in discovered and methods and len(methods) == len(set(methods)), 'Duplicate/empty class')
            discovered[name] = sorted(methods)
    require(discovered == data['classes'], 'UI source differs from reviewed method inventory')
    selected = [name for names in data['shards'].values() for name in names]
    require(all(data['shards'].values()), 'Empty shard')
    require(len(selected) == len(set(selected)), 'Duplicate required class')
    require(not set(selected) & set(data['optional']), 'Required class marked optional')
    require(set(selected) | set(data['optional']) == set(discovered), 'Missing or unknown class assignment')
    require(all(isinstance(reason, str) and reason.strip() for reason in data['optional'].values()), 'Missing exclusion reason')
    return data


def digest(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


def expected_tests(data, part):
    return sorted(f'{name}/{method}()' for name in data['shards'][part] for method in data['classes'][name])


def stages_for(part):
    require(part in PARTS, 'Unknown evidence part')
    return ('prepare', 'resolve', 'unit', 'release') if part == 'unit-release' else ('prepare', 'resolve', 'ui')


def identity():
    result = {key: os.environ.get(key, '') for key in IDENTITY_KEYS}
    require(all(result.values()), 'Incomplete run identity')
    require(all(re.fullmatch(r'[0-9a-f]{40}', result[key]) for key in IDENTITY_KEYS[:3]), 'Invalid SHA')
    require(all(re.fullmatch(r'[1-9][0-9]*', result[key]) for key in IDENTITY_KEYS[3:5]), 'Invalid run/attempt')
    return result


def test_identifiers(tree):
    found = []
    def visit(nodes):
        for node in nodes:
            if node.get('nodeType') == 'Test Case':
                require(node.get('result') == 'Passed', 'Non-passing UI case')
                identifier = node.get('nodeIdentifier', '')
                require(re.fullmatch(r'\w+/test\w+\(\)', identifier), 'Unknown UI identifier')
                require(node.get('nodeIdentifierURL', '').endswith('/DailyWhiskersUITests/' + identifier[:-2]), 'Wrong UI target')
                found.append(identifier)
            visit(node.get('children', []))
    visit(tree['testNodes'])
    require(found and len(found) == len(set(found)), 'Empty/duplicate UI test evidence')
    return sorted(found)


def device_environment(tests):
    devices = tests['devices']
    require(len(devices) == 1, 'Expected exactly one device/configuration')
    device = devices[0]['device']
    environment = {key: device[key] for key in DEVICE_KEYS}
    require(all(environment.values()), 'Missing device evidence')
    require(environment['deviceName'] == environment['modelName'] == 'iPhone 17 Pro'
            and environment['osVersion'] == '26.4.1' and environment['architecture'] == 'arm64'
            and environment['platform'] == 'iOS Simulator', 'Unexpected test destination')
    return environment


def annotate(output, directory, part, tree=None):
    data = inventory()
    output.update(part=part, identity=identity(), inventory_sha256=digest(data),
                  required_tests=[] if part == 'unit-release' else expected_tests(data, part))
    suite = 'unit' if part == 'unit-release' else 'ui'
    output['environment'] = {'toolchain': (directory / 'toolchain.txt').read_text().strip(),
                             'device': device_environment(output['stages'][suite]['tests'])}
    require(output['environment']['toolchain'], 'Missing toolchain')
    if part != 'unit-release':
        output['observed_tests'] = test_identifiers(tree)
        require(output['observed_tests'] == output['required_tests'], 'Missing/unknown UI tests')
        tests = output['stages']['ui']['tests']
        require(tests['totalTestCount'] == tests['executions'] == len(output['observed_tests']), 'UI count/identity mismatch')


def verify_record(record, part, data, current):
    from results import test_counts
    require(record.get('part') == part and record.get('verified') is True, 'Incomplete or wrong evidence part')
    require(record.get('identity') == current, 'Cross-source/checkout/run/attempt evidence')
    require(record.get('inventory_sha256') == digest(data), 'Stale inventory evidence')
    stages = record['stages']
    require(set(stages) == set(stages_for(part)), 'Missing/unknown stages')
    for stage in stages.values():
        require(stage.get('status') == 'success' and type(stage.get('exit_code')) is int
                and stage['exit_code'] == 0, 'Unsuccessful/incomplete command')
    suite = 'unit' if part == 'unit-release' else 'ui'
    tests = stages[suite]['tests']
    counts = test_counts(dict(tests, devicesAndConfigurations=tests.get('devices', [])))
    require(counts['valid_pass'], 'Non-passing test counts')
    require(record['environment']['device'] == device_environment(tests), 'Inconsistent device evidence')
    require(bool(record['environment']['toolchain']), 'Missing toolchain')
    required = [] if part == 'unit-release' else expected_tests(data, part)
    require(record.get('required_tests') == required, 'Wrong required inventory')
    if part != 'unit-release':
        observed = record.get('observed_tests', [])
        require(observed == required and counts['totalTestCount'] == counts['executions'] == len(required),
                'Incomplete/duplicate/unknown executed inventory')


def aggregate(directory):
    data, current = inventory(), identity()
    paths = list(directory.glob('*/results.json'))
    require(len(paths) == len(PARTS), 'Missing or extra evidence artifacts')
    records = [json.loads(path.read_text()) for path in paths]
    require(Counter(record.get('part') for record in records) == Counter(PARTS), 'Missing/duplicate/unknown part')
    for record in records:
        verify_record(record, record['part'], data, current)
    require(all(record['environment'] == records[0]['environment'] for record in records), 'Incompatible environments')
    print(f'Complete same-run evidence: unit, unsigned Release, and {sum(len(expected_tests(data, s)) for s in SHARDS)} UI tests across {len(SHARDS)} shards.')
    return records


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=('inventory', 'selectors', 'aggregate'))
    parser.add_argument('--shard', choices=SHARDS)
    parser.add_argument('--directory', type=Path, default=Path('build/evidence'))
    args = parser.parse_args()
    try:
        if args.command == 'aggregate':
            aggregate(args.directory)
        else:
            data = inventory()
            if args.command == 'selectors':
                require(args.shard is not None, 'Select a shard')
                for name in data['shards'][args.shard]:
                    print(f'-only-testing:DailyWhiskersUITests/{name}')
            else:
                print(json.dumps({s: expected_tests(data, s) for s in SHARDS}, indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        sys.exit(f'UI evidence rejected: {error}')

"""Reviewed UI inventory and fail-closed, same-run evidence aggregation."""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from simulator import BUILD, NAME, VERSION, verify_evidence, verify_toolchain
from cache_window import verify_record as verify_cache_record

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
    common = ('prepare', 'cache-window', 'cache-report', 'resolve')
    return (*common, 'unit', 'release', 'cleanup') if part == 'unit-release' else (*common, 'ui', 'cleanup')


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
    require(environment['deviceName'] == environment['modelName'] == NAME
            and environment['osVersion'] == VERSION and environment['osBuildNumber'] == BUILD
            and environment['architecture'] == 'arm64'
            and environment['platform'] == 'iOS Simulator', 'Unexpected test destination')
    return environment


def annotate(output, directory, part):
    """Preserve independent context without claiming it has passed validation."""
    from results import capture, read_object
    output.update(part=part, identity={key: os.environ.get(key, '') for key in IDENTITY_KEYS}, environment={})
    data = capture(output, 'inventory', lambda: read_object(ROOT / 'ci/ui-inventory.json'))
    if data is not None:
        output['inventory_sha256'] = digest(data)
        required = capture(output, 'required_tests', lambda: [] if part == 'unit-release' else expected_tests(data, part))
        if required is not None:
            output['required_tests'] = required
    toolchain = capture(output, 'toolchain', lambda: (directory / 'toolchain.txt').read_text().strip())
    if toolchain is not None:
        output['environment']['toolchain'] = toolchain
    for name, filename in (('budget', 'job-budget.json'), ('cache', 'cache-status.json'), ('simulator', 'simulator.json')):
        record = capture(output, name, lambda filename=filename: read_object(directory / filename))
        if record is not None:
            output[name] = record


def observe(output, part, tree):
    """Capture available observations independently; never fill them from pins."""
    from results import capture
    suite = 'unit' if part == 'unit-release' else 'ui'

    def observed_device():
        devices = output['stages'][suite]['reported_devices']
        require(isinstance(devices, list) and len(devices) == 1, 'Observed device unavailable or ambiguous')
        device = devices[0]['device']
        require(isinstance(device, dict) and device, 'Observed device unavailable')
        return {key: device[key] for key in DEVICE_KEYS if key in device}

    device = capture(output, 'device', observed_device)
    if device is not None:
        output['environment']['device'] = device
    if part != 'unit-release' and tree is not None:
        observed = capture(output, 'ui.tree', lambda: test_identifiers(tree))
        if observed is not None:
            output['observed_tests'] = observed


def verify_stages(stages, part, current, deadline):
    require(set(stages) == set(stages_for(part)), 'Missing/unknown stages')
    expected = {'source_sha': current['SOURCE_SHA'], 'tested_sha': current['TESTED_SHA'],
                'run_id': current['GITHUB_RUN_ID'], 'run_attempt': current['GITHUB_RUN_ATTEMPT'],
                'job': 'build-and-test' if part == 'unit-release' else 'ui-shards', 'shard': part}
    for name, stage in stages.items():
        require(stage.get('stage') == name, 'Mismatched stage name')
        require(all(stage.get(key) == value for key, value in expected.items()),
                'Cross-source/checkout/run/attempt/job/shard stage evidence')
        require(stage.get('status') == 'success' and type(stage.get('exit_code')) is int
                and stage['exit_code'] == 0, f"Unsuccessful/incomplete command: {name} status={stage.get('status')}, "
                f"wrapper exit={stage.get('exit_code')}, command exit={stage.get('command_exit_code')}")
        if name != 'cleanup':
            require(stage.get('deadline') == deadline, 'Execution stages disagree with the shared budget deadline')


def verify_record(record, part, data, current):
    require(record.get('verified') is True, f"Failed/incomplete {part} evidence: {record.get('evidence_error', 'no passing manifest')}")
    require(not record.get('evidence_errors'), f'{part} evidence contains unresolved collection errors')
    validate_record(record, part, data, current)


def validate_record(record, part, data, current):
    from results import test_counts
    require(record.get('part') == part, 'Wrong evidence part')
    require(record.get('identity') == current, 'Cross-source/checkout/run/attempt evidence')
    require(record.get('inventory_sha256') == digest(data), 'Stale inventory evidence')
    stages = record['stages']
    verify_stages(stages, part, current, record['budget']['deadline'])
    suite = 'unit' if part == 'unit-release' else 'ui'
    tests = stages[suite]['tests']
    counts = test_counts(dict(tests, devicesAndConfigurations=tests.get('devices', [])))
    require(counts['valid_pass'], 'Non-passing test counts')
    require(record['environment']['device'] == device_environment(tests), 'Inconsistent device evidence')
    verify_toolchain(record['environment']['toolchain'])
    verify_cache_record(record['cache'], current, part, record['budget'])
    simulator_id = verify_evidence(record['simulator'], stages['cleanup'], current, part)
    require(tests['devices'][0]['device'].get('deviceId') == simulator_id, 'Wrong observed simulator UUID')
    required = [] if part == 'unit-release' else expected_tests(data, part)
    require(record.get('required_tests') == required, 'Wrong required inventory')
    if part != 'unit-release':
        observed = record.get('observed_tests', [])
        require(observed == required, 'Missing/unknown UI tests')
        require(observed == required and counts['totalTestCount'] == counts['executions'] == len(required),
                'Incomplete/duplicate/unknown executed inventory')


def aggregate(directory):
    data, current = inventory(), identity()
    paths = list(directory.glob('*/results.json'))
    require(len(paths) == len(PARTS), 'Missing or extra evidence artifacts')
    records = [json.loads(path.read_text()) for path in paths]
    require(Counter(record.get('part') for record in records) == Counter(PARTS), 'Missing/duplicate/unknown part')
    for record in records:
        try:
            verify_record(record, record['part'], data, current)
        except (ValueError, KeyError, TypeError, AttributeError) as error:
            raise ValueError(f"{record['part']} evidence rejected: {error}") from error
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

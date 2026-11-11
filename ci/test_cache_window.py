"""Offline cache-window selection, observation and provenance tests."""
import copy
import json
from pathlib import Path
import re
import tempfile
import unittest

import cache_window as cache

ENV = dict(SOURCE_SHA='a' * 40, TESTED_SHA='b' * 40, GITHUB_RUN_ID='123', GITHUB_RUN_ATTEMPT='1',
           GITHUB_JOB='ui-shards', CI_PART='cards', CI_SHARD_ID='cards', CI_EXECUTION_DEADLINE='3700')


def budget(env=ENV):
    return {key: env[variable] for key, variable in cache.IDENTITY.items()} | {
        'started': 1000, 'execution_seconds': 2700, 'deadline': 3700}


def successful_record(env=ENV, classification='exact_hit'):
    now = 3600 if classification == 'skipped_budget' else 1100
    record = cache.window(budget(env), env, now)
    observation = dict(outcome='success', cache_hit='true', primary_key='exact-key', matched_key='exact-key')
    if classification == 'cold_miss':
        observation.update(cache_hit='', matched_key='')
    elif classification == 'partial_restore':
        observation.update(cache_hit='false', matched_key='other-key')
    elif classification == 'skipped_budget':
        observation = dict(outcome='skipped', cache_hit='', primary_key='', matched_key='')
    record.update(observation=observation, reported_at=now + 1, classification=classification, status='success')
    return record


class CacheWindowTests(unittest.TestCase):
    def test_minute_rounding_near_and_exhausted_deadlines(self):
        for remaining, minutes in ((2700, 5), (600, 5), (360, 5), (359.999, 4),
                                   (180, 2), (179.999, 1), (120, 1), (119.999, None),
                                   (60, None), (1, None), (0, None), (-300, None)):
            with self.subTest(remaining=remaining):
                record = cache.window(budget(), ENV, 3700 - remaining)
                self.assertEqual(record['timeout_minutes'], minutes)
                self.assertEqual(record['decision'], 'restore' if minutes else 'skip_insufficient_budget')
                if minutes:
                    self.assertLessEqual(minutes * 60 + 60, remaining)

    def test_missing_wrong_and_stale_identity_never_falls_back(self):
        for key in cache.IDENTITY:
            for change in ('remove', 'wrong'):
                data = budget()
                if change == 'remove':
                    data.pop(key)
                else:
                    data[key] = 'stale'
                with self.subTest(key=key, change=change), self.assertRaises(ValueError):
                    cache.window(data, ENV, 1100)
        for key in (*cache.IDENTITY.values(), 'TESTED_SHA', 'CI_PART'):
            for value in ('', 'invalid'):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    cache.window(budget(), ENV | {key: value}, 1100)

    def test_malformed_duration_timestamps_and_exported_deadline_rejected(self):
        for key in ('started', 'execution_seconds', 'deadline'):
            for value in (None, '', True, float('nan'), float('inf'), -1):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    cache.window(budget() | {key: value}, ENV, 1100)
        for mutation in ({'execution_seconds': 3600}, {'deadline': 3701}, {'started': 1101}):
            with self.assertRaises(ValueError):
                cache.window(budget() | mutation, ENV, 1100)
        for value in ('', 'invalid', 'nan', 'inf', '3701'):
            with self.assertRaises(ValueError):
                cache.window(budget(), ENV | {'CI_EXECUTION_DEADLINE': value}, 1100)
        for data in ([], None, 'budget'):
            with self.assertRaises(ValueError):
                cache.window(data, ENV, 1100)

    def test_skipped_output_is_finite_inert_and_budget_bytes_are_unchanged(self):
        for now, restore, minutes in ((1100, 'true', '5'), (3580, 'true', '1'),
                                      (3580.001, 'false', '1'), (3800, 'false', '1')):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                env = ENV | {'GITHUB_OUTPUT': str(directory / 'outputs')}
                path = directory / 'job-budget.json'
                original = json.dumps(budget(), indent=4) + '\n'
                path.write_text(original)
                self.assertEqual(cache.execute('plan', directory, env, now), 0)
                self.assertEqual((directory / 'outputs').read_text(), f'restore={restore}\ntimeout_minutes={minutes}\n')
                self.assertEqual(path.read_text(), original)
                self.assertNotIn('CI_EXECUTION_DEADLINE', (directory / 'outputs').read_text())
                self.assertEqual(env['CI_EXECUTION_DEADLINE'], '3700')

    def test_missing_or_unreadable_budget_writes_failure_without_restore_outputs(self):
        for contents in (None, 'not json', '[]'):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                if contents is not None:
                    (directory / 'job-budget.json').write_text(contents)
                env = ENV | {'GITHUB_OUTPUT': str(directory / 'outputs')}
                self.assertEqual(cache.execute('plan', directory, env, 1100), 1)
                self.assertFalse((directory / 'outputs').exists())
                record = json.loads((directory / 'cache-status.json').read_text())
                self.assertEqual(record['status'], 'failure')

    def test_classifications_are_distinct_and_validated_for_current_identity(self):
        for classification in ('exact_hit', 'cold_miss', 'partial_restore', 'skipped_budget'):
            record = successful_record(classification=classification)
            cache.verify_record(record, ENV, 'cards', budget())
            self.assertEqual(cache.classify(record, record['observation'], record['reported_at']), classification)

    def test_failure_cancellation_missing_outputs_and_late_restore_are_not_misses(self):
        record = successful_record()
        for change in ({'outcome': 'failure'}, {'outcome': 'cancelled'}, {'outcome': 'skipped'},
                       {'outcome': ''}, {'primary_key': ''}, {'matched_key': ''},
                       {'cache_hit': 'false'}, {'cache_hit': 'unknown'}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                cache.classify(record, record['observation'] | change, 1101)
        with self.assertRaises(ValueError):
            cache.classify(record, record['observation'], 3700.001)
        skipped = successful_record(classification='skipped_budget')
        with self.assertRaises(ValueError):
            cache.classify(skipped, record['observation'], 3601)

    def test_aggregate_rejects_tampered_window_and_stale_identity(self):
        original = successful_record()
        changes = [lambda d: d.update(classification='cold_miss'), lambda d: d.update(status='planned'),
                   lambda d: d.update(timeout_minutes=0), lambda d: d.update(timeout_minutes=6),
                   lambda d: d.update(startup_slack_seconds=0), lambda d: d.update(tested_sha='c' * 40),
                   lambda d: d.update(decision='skip_insufficient_budget'), lambda d: d.update(reported_at=3800)]
        changes += [lambda d, key=key: d.update({key: 'stale'}) for key in cache.IDENTITY]
        for change in changes:
            record = copy.deepcopy(original)
            change(record)
            with self.subTest(record=record), self.assertRaises(ValueError):
                cache.verify_record(record, ENV, 'cards', budget())

    def test_self_consistent_shifted_window_is_rejected_against_actual_shared_budget(self):
        record = successful_record()
        for key in ('started', 'deadline', 'planned_at', 'reported_at'):
            record[key] += 1000
        with self.assertRaises(ValueError):
            cache.verify_record(record, ENV, 'cards', budget())

    def test_report_is_durable_without_mutating_budget_or_masking_skip(self):
        for now, outcome, classification in ((1100, 'success', 'cold_miss'),
                                             (3600, 'skipped', 'skipped_budget'),
                                             (1100, 'failure', 'unavailable')):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                path = directory / 'job-budget.json'
                original = json.dumps(budget(), indent=4)
                path.write_text(original)
                env = ENV | {'GITHUB_OUTPUT': str(directory / 'outputs'), 'GITHUB_STEP_SUMMARY': str(directory / 'summary'),
                             'CACHE_OUTCOME': outcome, 'CACHE_HIT': '', 'CACHE_MATCHED_KEY': '',
                             'CACHE_PRIMARY_KEY': 'exact-key' if outcome != 'skipped' else ''}
                self.assertEqual(cache.execute('plan', directory, env, now), 0)
                self.assertEqual(cache.execute('report', directory, env, now + 1), 1 if outcome == 'failure' else 0)
                record = json.loads((directory / 'cache-status.json').read_text())
                self.assertEqual(record['classification'], classification)
                self.assertIn(classification, (directory / 'summary').read_text())
                self.assertEqual(path.read_text(), original)

    def test_changed_budget_and_repeated_plan_are_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            path = directory / 'job-budget.json'
            path.write_text(json.dumps(budget()))
            env = ENV | {'GITHUB_OUTPUT': str(directory / 'outputs'), 'GITHUB_STEP_SUMMARY': str(directory / 'summary')}
            self.assertEqual(cache.execute('plan', directory, env, 1100), 0)
            path.write_text(json.dumps(budget() | {'run_attempt': '2'}))
            self.assertEqual(cache.execute('report', directory, env, 1101), 1)
            self.assertEqual(cache.execute('plan', directory, env, 1102), 1)
            self.assertEqual(json.loads(path.read_text())['run_attempt'], '2')

    def test_workflow_guards_empty_zero_and_unknown_outputs_and_skips_empty_key_save(self):
        root = Path(__file__).resolve().parent.parent
        workflow = (root / '.github/workflows/ios.yml').read_text()
        jobs = dict(re.findall(r'^  ([\w-]+):\n(.*?)(?=^  [\w-]+:|\Z)', workflow, re.M | re.S))
        for job in ('build-and-test', 'ui-shards'):
            block = jobs[job]
            self.assertEqual(block.count('python3 ci/cache_window.py plan'), 1)
            self.assertEqual(block.count('python3 ci/cache_window.py report'), 1)
            self.assertIn('run-stage.py cache-window python3 ci/cache_window.py plan', block)
            self.assertIn('run-stage.py cache-report python3 ci/cache_window.py report', block)
            self.assertIn("if: ${{ always() && steps.cache-window.outcome == 'success' }}", block)
            self.assertIn("steps.cache-window.outputs.restore == 'true'", block)
            self.assertIn("contains(fromJSON('[\"1\",\"2\",\"3\",\"4\",\"5\"]'), steps.cache-window.outputs.timeout_minutes)", block)
            self.assertIn("timeout-minutes: ${{ fromJSON(steps.cache-window.outputs.timeout_minutes || '1') }}", block)
            self.assertIn('build/*-status.json', block)
        self.assertIn("if: success() && steps.packages.outcome == 'success' && steps.packages.outputs.cache-hit != 'true'", jobs['build-and-test'])

    def test_prepare_failure_cannot_start_cache_report_or_unwrapped_restore(self):
        root = Path(__file__).resolve().parent.parent
        workflow = (root / '.github/workflows/ios.yml').read_text()
        for job in ('build-and-test', 'ui-shards'):
            block = re.search(rf'^  {job}:\n(.*?)(?=^  [\w-]+:|\Z)', workflow, re.M | re.S)[1]
            steps = re.split(r'^      - ', block, flags=re.M)[1:]
            plan = next(step for step in steps if step.startswith('name: Bound dependency cache restore\n'))
            report = next(step for step in steps if step.startswith('name: Report cache state\n'))
            self.assertNotIn('if: always()', plan)
            self.assertIn('run-stage.py cache-window', plan)
            self.assertIn("if: ${{ always() && steps.cache-window.outcome == 'success' }}", report)
            self.assertIn('run-stage.py cache-report', report)
        # Actual expired-budget execution refusal is exercised by test_time_limits;
        # the workflow must not bypass it or add a report after a skipped plan.


if __name__ == '__main__':
    unittest.main()

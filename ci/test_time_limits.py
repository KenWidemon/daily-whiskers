"""Exercise real process shutdown and the actual UI invocation, without Xcode."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('bounded_runner', Path(__file__).with_name('run-stage.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
ROOT = Path(__file__).resolve().parent.parent


class TimeLimitTests(unittest.TestCase):
    def execute(self, code, seconds=0.3, grace=0.2):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            started = time.monotonic()
            result = runner.run('ui', [sys.executable, '-c', code], directory,
                                deadline=time.time() + seconds, grace_seconds=grace)
            record = json.loads((directory / 'ui-status.json').read_text())
            log = (directory / 'ui.log').read_text()
            self.assertLess(time.monotonic() - started, seconds + grace + 3)
            return result, record, log

    def test_slow_valid_command_keeps_its_success(self):
        code, record, log = self.execute('import time; time.sleep(.15); print("completed")', seconds=2)
        self.assertEqual(code, 0)
        self.assertEqual(record['status'], 'success')
        self.assertIn('completed', log)

    def test_silent_hang_is_terminated_and_recorded(self):
        code, record, _ = self.execute('import time; time.sleep(30)')
        self.assertEqual(code, 124)
        self.assertEqual(record['status'], 'timed_out')
        self.assertEqual(record['command_exit_code'], -signal.SIGTERM)

    def test_ignored_term_is_killed_with_bounded_cleanup(self):
        code, record, log = self.execute('import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); print("ready",flush=True); time.sleep(30)')
        self.assertEqual(code, 124)
        self.assertTrue(record['forced_kill'])
        self.assertEqual(record['command_exit_code'], -signal.SIGKILL)
        self.assertIn('ready', log)

    def test_successful_term_handler_cannot_turn_timeout_green(self):
        code, record, log = self.execute('import signal,time,sys; signal.signal(signal.SIGTERM, lambda *a: (print("evidence finalized",flush=True),sys.exit(0))); time.sleep(30)')
        self.assertEqual(code, 124)
        self.assertEqual(record['command_exit_code'], 0)
        self.assertIn('evidence finalized', log)

    def test_exhausted_budget_does_not_launch_later_stage(self):
        code, record, _ = self.execute('raise Exception("must not start")', seconds=-.01)
        self.assertEqual(code, 124)
        self.assertNotIn('command_exit_code', record)
        self.assertIn('not started', record['error'])

    def test_descendant_holding_pipe_does_not_stall_runner(self):
        code, record, log = self.execute('import subprocess,sys; p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(30)"]); print(p.pid,flush=True)')
        self.assertEqual(code, 124)
        self.assertEqual(record['command_exit_code'], 0)
        # Parent has exited, but its child's inherited pipe must still be bounded.
        self.assertTrue(log.strip().isdigit())

    def test_interruption_keeps_signal_and_failure(self):
        code, record, _ = self.execute('import os,signal,time; os.kill(os.getppid(),signal.SIGTERM); time.sleep(30)', seconds=2)
        self.assertEqual(code, 143)
        self.assertEqual(record['status'], 'interrupted')
        self.assertEqual(record['signal'], signal.SIGTERM)

    def test_budget_is_shared_across_stages_and_records_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            env_file = directory / 'env'
            with patch.dict(os.environ, {'GITHUB_ENV': str(env_file), 'SOURCE_SHA': 'head',
                                         'GITHUB_RUN_ID': '12', 'CI_SHARD_ID': 'saved'}):
                runner.initialize_budget(2, directory)
                deadline = float(env_file.read_text().split('=')[1])
                budget = json.loads((directory / 'job-budget.json').read_text())
                self.assertEqual(budget['deadline'], deadline)
                self.assertEqual(budget['shard'], 'saved')
                for stage in ('unit', 'ui'):
                    runner.run(stage, [sys.executable, '-c', 'pass'], directory, deadline=deadline)
                    record = json.loads((directory / f'{stage}-status.json').read_text())
                    self.assertEqual(record['deadline'], deadline)
                    self.assertEqual(record['source_sha'], 'head')
                    self.assertEqual(record['shard'], 'saved')

    def test_hosted_missing_or_invalid_deadline_fails_closed(self):
        for value in ('', 'nan', 'inf', 'invalid'):
            with tempfile.TemporaryDirectory() as temporary:
                env = os.environ | {'GITHUB_ACTIONS': 'true', 'CI_EXECUTION_DEADLINE': value}
                result = subprocess.run([sys.executable, str(ROOT / 'ci/run-stage.py'), 'ui', '/usr/bin/true'],
                                        cwd=temporary, env=env, capture_output=True)
                self.assertEqual(result.returncode, 2)

    def test_real_ui_command_enforces_default_and_max_without_retries(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lock = 'DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
            (directory / lock).parent.mkdir(parents=True)
            (directory / lock).write_text('locked')
            (directory / 'Package.resolved.expected').write_text('locked')
            fake = directory / 'xcodebuild'
            fake.write_text('#!/usr/bin/env python3\nimport json,os,sys\nfrom pathlib import Path\nPath(os.environ["CAPTURE"]).write_text(json.dumps(sys.argv[1:]))\n')
            fake.chmod(0o755)
            env = os.environ | {'PATH': str(directory) + os.pathsep + os.environ['PATH'],
                                'RUNNER_TEMP': str(directory), 'GITHUB_WORKSPACE': str(directory),
                                'SIMULATOR_ID': 'fake', 'CAPTURE': str(directory / 'args.json')}
            subprocess.run(['bash', str(ROOT / 'ci/test-app.sh'), 'ui'], cwd=directory, env=env, check=True)
            args = json.loads((directory / 'args.json').read_text())
            for flag, value in (('-test-timeouts-enabled', 'YES'),
                                ('-default-test-execution-time-allowance', '720'),
                                ('-maximum-test-execution-time-allowance', '720')):
                self.assertEqual(args.count(flag), 1)
                self.assertEqual(args[args.index(flag) + 1], value)
            for forbidden in ('-retry-tests-on-failure', '-test-iterations', '-run-tests-until-failure'):
                self.assertNotIn(forbidden, args)
            self.assertFalse(any(arg.startswith('-skip-testing') for arg in args))


if __name__ == '__main__':
    unittest.main()

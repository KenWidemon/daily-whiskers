"""Offline subprocess fixtures only. No Apple tools or simulator commands."""
import errno
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import probe_supervisor as supervisor


class SupervisorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def runner(self, seconds=3, shutdown=.5):
        return supervisor.Supervisor(self.root, 'fixture', seconds, shutdown)

    def test_success_records_direct_exec_pid_timing_output_and_reaping(self):
        with self.runner() as run:
            result = run.run('identity', [sys.executable, '-c', 'import os; print(os.getpid())'])
        record = run.commands[0]
        self.assertEqual(int(result), record['pid'])
        self.assertEqual(record['pid'], record['pgid'])
        self.assertTrue(record['exec_attempt_observed'])
        self.assertTrue(record['reaped'])
        self.assertTrue(record['group_absent'])
        self.assertEqual(record['exit_code'], 0)
        self.assertLessEqual(record['monotonic_start'], record['exec_monotonic'])
        self.assertLessEqual(record['exec_monotonic'], record['monotonic_end'])
        self.assertEqual(json.loads(next(self.root.glob('*identity.json')).read_text()), record)

    def test_partial_output_survives_timeout_and_no_next_protected_command(self):
        with self.runner() as run:
            with self.assertRaises(supervisor.CommandFailure):
                run.run('slow', [sys.executable, '-c', 'import time; print("partial", flush=True); time.sleep(3)'], .1)
            with self.assertRaises(supervisor.CommandFailure):
                run.run('late', [sys.executable, '-c', 'raise Exception("must not execute")'])
        self.assertIn('partial', next(self.root.glob('*slow.log')).read_text())
        self.assertEqual(run.commands[0]['status'], 'timed_out')
        self.assertTrue(run.commands[0]['reaped'])
        self.assertTrue(run.commands[0]['group_absent'])
        self.assertFalse(run.commands[1]['launch_authorized'])
        self.assertIsNone(run.commands[1]['pid'])

    def test_expired_shared_or_operation_deadline_never_forks(self):
        for shared in (True, False):
            run = self.runner(seconds=0 if shared else 5)
            with patch.object(supervisor.os, 'fork') as fork:
                with self.assertRaises(supervisor.CommandFailure):
                    run.run('expired', ['never'], absolute_deadline=None if shared else time.monotonic() - 1)
            fork.assert_not_called()

    def test_child_checks_deadline_after_gate_before_exec(self):
        # Invoke only the child helper with mocked syscalls; late permission cannot exec.
        with patch.object(supervisor.os, 'setsid'), patch.object(supervisor.os, 'dup2'), \
                patch.object(supervisor.os, 'write'), patch.object(supervisor.os, 'read', return_value=b'G'), \
                patch.object(supervisor.os, 'execvp') as execute, \
                patch.object(supervisor.os, '_exit', side_effect=SystemExit), \
                patch.object(supervisor.signal, 'signal'):
            with self.assertRaises(SystemExit):
                supervisor.child_exec(['never'], 1, 2, 3, time.monotonic() - 1)
            execute.assert_not_called()

    def test_delayed_fork_return_cannot_authorize_late_exec(self):
        real_fork = os.fork
        marker = self.root / 'must-not-exist'
        def delayed_fork():
            pid = real_fork()
            if pid:
                time.sleep(.12)
            return pid
        with self.runner() as run, patch.object(supervisor.os, 'fork', side_effect=delayed_fork):
            with self.assertRaises(supervisor.CommandFailure):
                run.run('late-fork', [sys.executable, '-c', f'open({str(marker)!r}, "w").write("bad")'], .05)
        self.assertFalse(marker.exists())
        self.assertFalse(run.commands[0]['launch_authorized'])

    def test_nonzero_and_missing_executable_fail_closed(self):
        for argv in ([sys.executable, '-c', 'raise SystemExit(7)'], ['/no/such/probe-fixture']):
            with self.runner() as run:
                with self.assertRaises(supervisor.CommandFailure):
                    run.run('failure', argv)
            self.assertTrue(run.commands[0]['reaped'])
            self.assertNotEqual(run.commands[0]['exit_code'], 0)

    def test_output_limit_preserves_prefix_and_fails(self):
        with self.runner() as run, patch.object(supervisor, 'OUTPUT_LIMIT', 32):
            with self.assertRaises(supervisor.CommandFailure):
                run.run('output', [sys.executable, '-c', 'print("x" * 500)'])
        self.assertEqual(len(next(self.root.glob('*output.log')).read_bytes()), 32)
        self.assertTrue(run.commands[0]['output_truncated'])

    def test_term_ignoring_fixture_is_killed_and_reaped_within_reserve(self):
        with self.runner() as run:
            with self.assertRaises(supervisor.CommandFailure):
                run.run('ignore-term', [sys.executable, '-c',
                    'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); '
                    'print("ready", flush=True); time.sleep(3)'], .15)
        record = run.commands[0]
        self.assertTrue(record['reaped'])
        self.assertTrue(record['group_absent'])
        self.assertEqual(record['exit_code'], -signal.SIGKILL)
        self.assertLess(record['duration_seconds'], 1)

    def test_same_group_descendant_is_killed_after_exec_parent_exits(self):
        descendant = 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); print("descendant", flush=True); time.sleep(3)'
        parent = ('import subprocess,sys,time; '
                  f'subprocess.Popen([sys.executable, "-c", {descendant!r}]); '
                  'time.sleep(.1)')
        with self.runner() as run:
            with self.assertRaises(supervisor.CommandFailure):
                run.run('descendant', [sys.executable, '-c', parent])
        record = run.commands[0]
        self.assertEqual(record['status'], 'descendants_unresolved')
        self.assertEqual(record['exit_code'], 0)
        self.assertTrue(record['reaped'])
        self.assertTrue(record['group_absent'])
        self.assertIn('descendant', next(self.root.glob('*descendant.log')).read_text())

    def test_unexpected_controller_error_uses_bounded_final_reap(self):
        with self.runner() as run, patch.object(supervisor.selectors, 'DefaultSelector', side_effect=OSError('fixture')):
            with self.assertRaises(supervisor.CommandFailure):
                run.run('controller-error', [sys.executable, '-c', 'print("never")'])
        record = run.commands[0]
        self.assertEqual(record['status'], 'supervisor_error')
        self.assertTrue(record['reaped'])
        self.assertTrue(record['group_absent'])

    def test_controller_error_cannot_restart_consumed_shutdown_reserve(self):
        real_selector = supervisor.selectors.DefaultSelector
        with self.runner(shutdown=1) as run:
            class ErrorDuringShutdown:
                def __init__(self):
                    self.inner = real_selector()
                    self.raised = False
                def __enter__(self):
                    return self
                def __exit__(self, *args):
                    self.inner.close()
                def register(self, *args):
                    return self.inner.register(*args)
                def unregister(self, *args):
                    return self.inner.unregister(*args)
                def get_map(self):
                    return self.inner.get_map()
                def select(self, timeout):
                    if run.commands[0]['status'] == 'timed_out' and not self.raised:
                        self.raised = True
                        time.sleep(.5)  # Consume part of the existing absolute reserve.
                        raise OSError('injected during shutdown')
                    return self.inner.select(timeout)
            with patch.object(supervisor.selectors, 'DefaultSelector', ErrorDuringShutdown), \
                    patch.object(supervisor, 'group_absent', return_value=False):
                with self.assertRaises(supervisor.CommandFailure):
                    run.run('reserve-error', [sys.executable, '-c',
                        'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(3)'], .1)
        record = run.commands[0]
        self.assertTrue(record['reaped'])
        self.assertFalse(record['group_absent'])  # Deliberately unavailable independent readback.
        self.assertEqual(record['status'], 'supervisor_error')
        # Normal-scheduling regression: the old reset consumed about 1.6 seconds.
        self.assertLess(record['duration_seconds'], 1.35)

    def test_denied_group_signals_do_not_claim_reaping_or_containment(self):
        # Fixture exits naturally, so this test leaves no live process behind.
        real_killpg = os.killpg
        def denied_signal(pid, number):
            if number:
                raise PermissionError(errno.EPERM, 'denied fixture')
            return real_killpg(pid, number)
        with self.runner() as run, patch.object(supervisor.os, 'killpg', side_effect=denied_signal):
            with self.assertRaises(supervisor.CommandFailure):
                run.run('denied', [sys.executable, '-c', 'import time; time.sleep(.25)'], .1)
        record = run.commands[0]
        self.assertEqual(record['status'], 'timed_out')
        self.assertTrue(record['signal_errors'])
        self.assertTrue(record['reaped'])  # Independently observed natural exit only.
        self.assertTrue(record['group_absent'])

    def test_denied_signals_and_group_inspection_remain_uncertain(self):
        record = {}
        with patch.object(supervisor.os, 'killpg', side_effect=PermissionError(errno.EPERM, 'denied')):
            supervisor.signal_group(123, signal.SIGTERM, record)
            self.assertIsNone(supervisor.group_absent(123))
        self.assertEqual(record['signal_errors'][0]['errno'], errno.EPERM)

    def test_unreaped_or_uncertain_group_blocks_even_evidence_launch(self):
        for reaped, absent in ((False, True), (True, None), (True, False)):
            run = self.runner()
            run.commands.append({'status': 'failure', 'reaped': reaped, 'group_absent': absent})
            with patch.object(supervisor.os, 'fork') as fork:
                with self.assertRaises(supervisor.CommandFailure):
                    run.run('evidence', ['never'], evidence=True)
            fork.assert_not_called()

    def test_interrupted_controller_does_not_launch(self):
        run = self.runner()
        run.interrupt(signal.SIGTERM, None)
        with patch.object(supervisor.os, 'fork') as fork:
            with self.assertRaises(supervisor.CommandFailure):
                run.run('interrupted', ['never'])
        fork.assert_not_called()

    def test_evidence_cannot_reset_shared_deadline(self):
        run = self.runner(seconds=0)
        with self.assertRaises(supervisor.CommandFailure):
            run.run('evidence', ['never'], evidence=True)
        self.assertIsNone(run.commands[-1]['pid'])

    def test_command_count_is_capped(self):
        run = self.runner()
        with patch.object(supervisor, 'COMMAND_LIMIT', 0), patch.object(supervisor.os, 'fork') as fork:
            with self.assertRaises(supervisor.CommandFailure):
                run.run('extra', ['never'])
        fork.assert_not_called()


if __name__ == '__main__':
    unittest.main()

"""Offline observer fixtures; bounded synthetic processes, never product execution."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

import diagnostic as d
import diagnostic_monitor as m
from test_diagnostic import ENV, UUID


class HelperTests(unittest.TestCase):
    def setUp(self):
        self.budget = patch.object(m, '_helper_calls', 0)
        self.budget.start()
        self.addCleanup(self.budget.stop)

    def test_success_and_nonzero(self):
        self.assertEqual(m.host_output([sys.executable, '-c', 'print("ok")'], until=time.time()+10), 'ok')
        with self.assertRaises(subprocess.CalledProcessError) as caught:
            m.host_output([sys.executable, '-c', 'print("permission denied"); exit(2)'], until=time.time()+10)
        self.assertIn('permission denied', caught.exception.output)

    def test_timeout_reaps_exact_helper_group(self):
        started = time.monotonic()
        with self.assertRaises(m.ReapedHelperTimeout) as caught:
            m.host_output([sys.executable, '-c', 'import time; time.sleep(30)'], seconds=.1, until=time.time()+5)
        error = caught.exception
        self.assertTrue(error.cleanup['reaped'])
        self.assertTrue(error.cleanup['group_absent'])
        self.assertLess(time.monotonic()-started, 3)
        self.assertRaises(ProcessLookupError, os.killpg, error.cleanup['pid'], 0)

    def test_descendant_held_pipe_is_bounded_and_group_absent(self):
        command = [sys.executable, '-c',
                   'import subprocess,time; subprocess.Popen(["/bin/sleep","30"]); time.sleep(30)']
        started = time.monotonic()
        with self.assertRaises(m.ReapedHelperTimeout) as caught:
            m.host_output(command, seconds=.15, until=time.time()+5)
        self.assertLess(time.monotonic()-started, 3)
        self.assertRaises(ProcessLookupError, os.killpg, caught.exception.cleanup['pid'], 0)

    def test_output_bound(self):
        with self.assertRaisesRegex(ValueError, 'output exceeds'):
            m.host_output([sys.executable, '-c', 'print("x" * 3000000)'], until=time.time()+10)

    def test_deadline_reserves_cleanup_without_launch(self):
        with patch.object(m.subprocess, 'Popen') as launch:
            self.assertRaises(ValueError, m.host_output, ['helper'], until=time.time()+1)
            launch.assert_not_called()

    def test_interruption_reaps_before_propagating(self):
        real_read = os.read
        launched = []
        real_popen = subprocess.Popen
        def launch(*args, **kwargs):
            process = real_popen(*args, **kwargs)
            launched.append(process)
            return process
        def interrupted(fd, size):
            if launched:
                raise SystemExit(143)
            return real_read(fd, size)
        with patch.object(m.subprocess, 'Popen', side_effect=launch), patch.object(m.os, 'read', side_effect=interrupted):
            self.assertRaises(SystemExit, m.host_output, [sys.executable, '-c', 'print("ready", flush=True); import time; time.sleep(30)'], until=time.time()+10)
        self.assertIsNotNone(launched[0].returncode)
        self.assertRaises(ProcessLookupError, os.killpg, launched[0].pid, 0)

    def test_pending_cancellation_at_launch_reaps_owned_group(self):
        launched = []
        real_popen = subprocess.Popen
        def launch(*args, **kwargs):
            process = real_popen(*args, **kwargs)
            launched.append(process)
            os.kill(os.getpid(), signal.SIGTERM)
            return process
        def interrupted(signum, frame):
            raise SystemExit(128 + signum)
        previous = signal.signal(signal.SIGTERM, interrupted)
        try:
            with patch.object(m.subprocess, 'Popen', side_effect=launch):
                self.assertRaises(SystemExit, m.host_output,
                                  [sys.executable, '-c', 'import time; time.sleep(30)'],
                                  until=time.time()+10)
        finally:
            signal.signal(signal.SIGTERM, previous)
        self.assertIsNotNone(launched[0].returncode)
        self.assertRaises(ProcessLookupError, os.killpg, launched[0].pid, 0)

    def test_output_close_failure_occurs_after_verified_cleanup(self):
        process = Mock(pid=999999, stdout=Mock(), returncode=0)
        process.poll.return_value = 0
        process.stdout.close.side_effect = OSError('close failed')
        selector = Mock()
        selector.get_map.return_value = {}
        with patch.object(m.subprocess, 'Popen', return_value=process), \
             patch.object(m.selectors, 'DefaultSelector') as factory, \
             patch.object(m.os, 'killpg', side_effect=[None, ProcessLookupError()]) as kill:
            factory.return_value.__enter__.return_value = selector
            with self.assertRaises(m.HelperCleanupError) as caught:
                m.host_output(['helper'], until=time.time()+10)
            self.assertIn('close_output', str(caught.exception))
            self.assertEqual(kill.call_count, 2)
            process.wait.assert_called_once()

    def test_kill_denial_and_reap_timeout_are_fatal(self):
        # Synthetic process objects avoid leaving real children when denial is injected.
        for error in (PermissionError('denied'), subprocess.TimeoutExpired('helper', 2)):
            process = Mock(pid=999999, stdout=Mock(), returncode=None)
            process.stdout.fileno.return_value = 0
            process.poll.return_value = 0
            process.wait.side_effect = error if isinstance(error, subprocess.TimeoutExpired) else None
            selector = Mock()
            selector.get_map.return_value = {}
            with patch.object(m.subprocess, 'Popen', return_value=process), \
                 patch.object(m.selectors, 'DefaultSelector') as factory, \
                 patch.object(m.os, 'killpg', side_effect=error if isinstance(error, PermissionError) else None):
                factory.return_value.__enter__.return_value = selector
                with self.assertRaises(m.HelperCleanupError) as caught:
                    m.host_output(['helper'], until=time.time()+10)
                self.assertIn('999999', str(caught.exception))
                self.assertIn('cleanup_confirmed', str(caught.exception))


class DiscoveryTimeoutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        for item in (patch.object(d, 'DIAGNOSTIC', Path(self.temp.name)), patch.dict(os.environ, ENV),
                     patch.object(d, 'owned', return_value={'simulator_id': UUID})):
            item.start()
            self.addCleanup(item.stop)
        self.metadata = {'lane': 'cards', 'bundles': {'runner': {'bundle_id': 'runner', 'executable': 'Runner'}}}
        self.command = ['xcrun', 'simctl', 'get_app_container', UUID, 'runner', 'app']
        self.instance = m.Monitor('cards', 'cards-largest', Mock(pid=42), self.metadata, 1000, started=100)

    def timeout(self, command=None, output=''):
        error = m.ReapedHelperTimeout(command or self.command, 3, output=output)
        error.cleanup = {'pid': 99, 'group_absent': True, 'reaped': True}
        return error

    def test_timeout_then_success_does_not_relaunch(self):
        with patch.object(m, 'container', side_effect=[self.timeout(), Path('/owned/app'), Path('/owned/data')]), \
             patch.object(m, 'discover_runner', return_value=123), patch.object(m.subprocess, 'Popen') as launch:
            with patch.object(m.time, 'time', return_value=100):
                self.instance.discover()
            self.assertIsNone(self.instance.runner_pid)
            self.assertFalse(self.instance.test_started)
            with patch.object(m.time, 'time', return_value=105):
                self.instance.discover()
            self.assertEqual(self.instance.runner_pid, 123)
            self.assertFalse(self.instance.test_started)
            launch.assert_not_called()

    def test_repeated_timeouts_exhaust_original_window(self):
        with patch.object(m, 'container', side_effect=self.timeout()) as container:
            for now in range(100, 400, 5):
                with patch.object(m.time, 'time', return_value=now):
                    self.instance.discover()
            self.assertEqual(container.call_count, 60)
            self.assertEqual(len(self.instance.report['container_unavailable']), 60)
            with patch.object(m.time, 'time', return_value=400):
                self.assertRaises(ValueError, self.instance.tick)
            self.assertIsNone(self.instance.runner_pid)
            self.assertFalse(self.instance.test_started)

    def test_foreign_permission_malformed_and_ps_timeouts_fail(self):
        for error in [self.timeout(['/bin/ps']), self.timeout(output='permission denied'),
                      self.timeout(output='malformed'), subprocess.TimeoutExpired(self.command, 3)]:
            with patch.object(m, 'container', side_effect=error), patch.object(m.time, 'time', return_value=100):
                self.instance.next_discovery = 0
                self.assertRaises((ValueError, subprocess.TimeoutExpired), self.instance.discover)
        with patch.object(m, 'container', return_value=Path('/owned')), \
             patch.object(m, 'discover_runner', side_effect=self.timeout(['/bin/ps'])), \
             patch.object(m.time, 'time', return_value=100):
            self.instance.next_discovery = 0
            self.assertRaises(m.ReapedHelperTimeout, self.instance.discover)


if __name__ == '__main__':
    unittest.main()

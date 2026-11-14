"""Offline CLI and lifecycle fixtures; no real sampler, app or process inspection."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock,patch
import launch_observation as o

BOOTSTRAP=Path(o.__file__).with_name('launch_capture_bootstrap.py')
LINE=b'    t = 1.00s Launch com.example.kenwidemon.dailywhiskers\n'

class Receipts(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.launch={'pid':123,'command':['xcodebuild'],'deadline':time.time()+30}
    def cli(self,source,directory=None):
        # Import stubs sit next to an unchanged copy of the real bootstrap.
        shutil.copyfile(BOOTSTRAP,self.root/'launch_capture_bootstrap.py')
        (self.root/'launch_observation.py').write_text(source)
        payload={'launch':self.launch,'directory':str(directory or self.root),'line':'synthetic','received':{}}
        return subprocess.run([sys.executable,'-B',str(self.root/'launch_capture_bootstrap.py'),'--capture',json.dumps(payload)],
                              start_new_session=True,capture_output=True,text=True,timeout=5)
    def test_actual_observer_cli_rejects_invalid_target_without_tools(self):
        self.launch['command']=['invalid-target']
        result=self.cli(Path(o.__file__).read_text())
        self.assertEqual(result.returncode,0)
        record=json.loads((self.root/'host-observation.json').read_text())
        self.assertEqual(record['status'],'inconclusive')
        self.assertIn('Wrong child',record['error'])
        self.assertFalse((self.root/'sampler-lifecycle.json').exists())
    def test_final_bootstrap_persistence_error_is_retained_on_stderr(self):
        source='from pathlib import Path\ndef observe(*a):\n def fail(*a,**k): raise OSError("final write failed")\n Path.write_text=fail\n'
        result=self.cli(source)
        self.assertEqual(result.returncode,1);self.assertIn('final write failed',result.stderr)
        self.assertEqual(json.loads((self.root/'observer-bootstrap.json').read_text())['status'],'imported')
    def test_import_failure_retained_in_bootstrap_and_stderr(self):
        result=self.cli('raise ImportError("synthetic import failure")')
        self.assertEqual(result.returncode,1);self.assertIn('synthetic import failure',result.stderr)
        record=json.loads((self.root/'observer-bootstrap.json').read_text())
        self.assertEqual(record['status'],'error');self.assertEqual(record['errors'][0]['type'],'ImportError')
    def test_missing_final_receipt_distinct_from_successful_worker_return(self):
        result=self.cli('def observe(*a): pass')
        self.assertEqual(result.returncode,0);self.assertFalse((self.root/'host-observation.json').exists())
        self.assertEqual(json.loads((self.root/'observer-bootstrap.json').read_text())['status'],'returned')
    def test_bootstrap_persistence_failure_is_nonzero_and_retains_stderr(self):
        result=self.cli('def observe(*a): raise AssertionError("must not run")',self.root/'missing')
        self.assertEqual(result.returncode,1);self.assertIn('persistence failed',result.stderr);self.assertNotIn('must not run',result.stderr)
    def test_worker_runtime_error_keeps_specific_error(self):
        result=self.cli('def observe(*a): raise RuntimeError("capture failed")')
        self.assertEqual(result.returncode,1);self.assertIn('capture failed',result.stderr)
    def test_independent_alarm_terminates_stuck_stub(self):
        start=time.monotonic();result=self.cli('import time\ndef observe(*a): time.sleep(30)')
        self.assertEqual(result.returncode,-signal.SIGKILL);self.assertLess(time.monotonic()-start,5)
        self.assertEqual(json.loads((self.root/'observer-bootstrap.json').read_text())['status'],'imported')
    def test_stop_worker_records_nonzero_exit_and_signal_reap_timing(self):
        child=subprocess.Popen([sys.executable,'-c','raise SystemExit(23)'],start_new_session=True)
        time.sleep(.1);result=o.stop_worker(child)
        self.assertEqual(result['worker_exit_code'],23);self.assertTrue(result['reaped'])
        self.assertGreaterEqual(result['finished_monotonic_ns'],result['cleanup_requested_monotonic_ns'])
    def test_denied_cleanup_still_reaps_worker_and_reports_uncertainty(self):
        child=Mock(pid=42);child.wait.return_value=23
        with patch.object(o.os,'killpg',side_effect=PermissionError('denied')):result=o.stop_worker(child)
        self.assertEqual(result['worker_exit_code'],23);self.assertTrue(result['reaped'])
        self.assertEqual(result['signal_result'],'unverified');child.wait.assert_called_once_with(timeout=.75)
    def test_sampler_write_failure_kills_exact_spawned_stub(self):
        child=Mock(pid=456);child.wait.return_value=-9
        calls=0
        def fail_second(*a):
            nonlocal calls
            calls+=1
            if calls==2:raise OSError('spawn persistence failure')
        with patch.object(o.subprocess,'Popen',return_value=child),patch.object(o,'write',side_effect=fail_second):
            self.assertRaises(OSError,o.run_sampler,['stub'],None,time.monotonic()+1,self.root/'sampler.json')
        child.kill.assert_called_once();child.wait.assert_called_once_with(timeout=.25)
    def test_sampler_timeout_retains_cleanup_bookkeeping(self):
        child=Mock(pid=456);child.wait.side_effect=[subprocess.TimeoutExpired('stub',1),-9]
        with patch.object(o.subprocess,'Popen',return_value=child):
            self.assertRaises(subprocess.TimeoutExpired,o.run_sampler,['stub'],None,time.monotonic()+1,self.root/'sampler.json')
        record=json.loads((self.root/'sampler.json').read_text());self.assertTrue(record['reaped']);self.assertEqual(record['exit_code'],-9);child.kill.assert_called_once()
    def test_sampler_denied_kill_still_reaps_and_retains_primary_timeout(self):
        for reaped in (True,False):
            child=Mock(pid=456)
            child.kill.side_effect=PermissionError('kill denied')
            child.wait.side_effect=[subprocess.TimeoutExpired('original',1),23 if reaped else subprocess.TimeoutExpired('reap',.25)]
            with patch.object(o.subprocess,'Popen',return_value=child):
                with self.assertRaises(subprocess.TimeoutExpired) as caught:
                    o.run_sampler(['stub'],None,time.monotonic()+1,self.root/'sampler.json')
            self.assertEqual(caught.exception.cmd,'original')
            record=json.loads((self.root/'sampler.json').read_text())
            self.assertEqual(record['signal_result'],'unverified');self.assertEqual(record['reaped'],reaped)
            self.assertIn('finished',record);self.assertEqual(child.wait.call_count,2)
    def test_final_sampler_write_error_does_not_replace_primary_timeout(self):
        child=Mock(pid=456);child.wait.side_effect=[subprocess.TimeoutExpired('original',1),-9]
        original=o.write;calls=0
        def fail_final(*args):
            nonlocal calls
            calls+=1
            if calls==3:raise OSError('final persistence denied')
            original(*args)
        with patch.object(o.subprocess,'Popen',return_value=child),patch.object(o,'write',side_effect=fail_final),patch.object(o.sys,'stderr'):
            with self.assertRaises(subprocess.TimeoutExpired) as caught:o.run_sampler(['stub'],None,time.monotonic()+1,self.root/'sampler.json')
        self.assertEqual(caught.exception.cmd,'original')
    def test_interruption_receipt_and_original_signal_preserved(self):
        termination={'worker_exit_code':-9,'reaped':True,'signal_result':'sent'}
        with patch.object(o,'stop_worker',return_value=termination),patch.object(o.signal,'signal') as reset,patch.object(o.os,'kill') as kill:
            o.handle_interruption(Mock(),signal.SIGTERM,self.root)
        record=json.loads((self.root/'observer-interruption.json').read_text())
        self.assertEqual(record['termination'],termination);self.assertEqual(record['signal'],signal.SIGTERM)
        reset.assert_called_once_with(signal.SIGTERM,signal.SIG_DFL);kill.assert_called_once_with(os.getpid(),signal.SIGTERM)
    def test_interruption_write_failure_still_preserves_signal(self):
        with patch.object(o,'stop_worker',side_effect=PermissionError('cleanup denied')),patch.object(o,'write',side_effect=OSError('write denied')),patch.object(o.sys,'stderr'),patch.object(o.signal,'signal'),patch.object(o.os,'kill') as kill:
            o.handle_interruption(Mock(),signal.SIGTERM,self.root)
        kill.assert_called_once_with(os.getpid(),signal.SIGTERM)
    def test_parent_retains_stderr_nonzero_and_child_stdout_exit(self):
        selected=subprocess.Popen([sys.executable,'-c','import os;os.write(1,'+repr(LINE+b'tail\n')+');raise SystemExit(65)'],stdout=subprocess.PIPE)
        original=subprocess.Popen
        def fake_worker(*args,**kwargs):
            return original([sys.executable,'-c','import sys;print("observer startup error",file=sys.stderr);raise SystemExit(27)'],**kwargs)
        with patch.object(o.subprocess,'Popen',side_effect=fake_worker),patch.object(o.os,'write',side_effect=lambda fd,b:len(b)):
            code,record=o.forward(selected,self.launch,self.root)
        self.assertEqual(code,65);self.assertEqual((self.root/'stdout.raw').read_bytes(),LINE+b'tail\n')
        self.assertEqual(record['worker_termination']['worker_exit_code'],27)
        self.assertIn('observer startup error',record['worker_stderr']['excerpt'])
        self.assertEqual(record['worker_final_receipt'],'missing-or-incomplete')
    def test_parent_spawn_receipt_failure_never_starts_worker_or_changes_child_exit(self):
        selected=subprocess.Popen([sys.executable,'-c','import os;os.write(1,'+repr(LINE)+');raise SystemExit(65)'],stdout=subprocess.PIPE)
        original=o.write
        def fail(path,value):
            if path.name=='observer-parent.json':raise OSError('parent receipt denied')
            return original(path,value)
        with patch.object(o,'write',side_effect=fail),patch.object(o.subprocess,'Popen') as spawn,patch.object(o.os,'write',side_effect=lambda fd,b:len(b)):
            code,record=o.forward(selected,self.launch,self.root)
        spawn.assert_not_called();self.assertEqual(code,65);self.assertTrue(record['errors'])

if __name__=='__main__':unittest.main()

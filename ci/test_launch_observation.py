"""Offline synthetic host-observation cases. Never runs sample or Xcode."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock,patch
import launch_observation as o

LINE=b'    t =     3.88s         Launch com.example.kenwidemon.dailywhiskers\n'

class TriggerTests(unittest.TestCase):
    def test_fragmented_exact_line_latches_only_once(self):
        t=o.Trigger()
        self.assertIsNone(t.feed(LINE[:20]))
        self.assertIn('Launch',t.feed(LINE[20:]))
        self.assertIsNone(t.feed(LINE))
    def test_long_foreign_and_unterminated_lines_do_not_trigger(self):
        t=o.Trigger()
        self.assertIsNone(t.feed(b'x'*70000+LINE))
        self.assertIsNone(t.feed(LINE.replace(b'dailywhiskers',b'foreign')))
        self.assertIsNone(t.feed(LINE[:-1]))
        self.assertIsNotNone(t.feed(b'\n'))
        self.assertEqual(t.long_lines,1)
    def test_multiple_lines_one_chunk(self):
        t=o.Trigger(); self.assertIsNotNone(t.feed(b'other\n'+LINE+LINE))
    def test_missing_line(self):
        self.assertIsNone(o.Trigger().feed(b'no launch\n'))

class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.path=Path(self.temp.name);self.process=Mock(pid=42)
        self.launch={'pid':42,'command':['xcodebuild','test-without-building'],'deadline':time.time()+30}
    def read(self):return json.loads((self.path/'host-observation.json').read_text())
    def run_sample(self,command,*args,**kwargs):
        (self.path/'host-xcodebuild.sample.txt').write_text('Process: xcodebuild [42]\nCall graph:\n')
        return 0
    def execute(self,**kwargs):o.observe(self.process,self.launch,self.path,LINE.decode(),**kwargs)
    def test_success_is_unqualified_not_pre_expiry(self):
        with patch.object(o,'snapshot',return_value='owned'),patch.object(o,'run_sampler',side_effect=self.run_sample):self.execute()
        r=self.read();self.assertEqual(r['status'],'captured-unqualified');self.assertIn('unverified',r['pre_expiry'])
        self.assertEqual(r['sample_command'][1:4],['42','1','10'])
    def test_late_shared_deadline_does_not_sample(self):
        self.launch['deadline']=time.time()-1
        with patch.object(o,'run_sampler') as run:self.execute();run.assert_not_called()
        self.assertEqual(self.read()['status'],'inconclusive')
    def test_wrong_pid_does_not_sample(self):
        self.launch['pid']=99
        with patch.object(o,'run_sampler') as run:self.execute();run.assert_not_called()
        self.assertEqual(self.read()['status'],'inconclusive')
    def test_child_exited_or_snapshot_mismatch(self):
        for error in [ValueError('zombie'),subprocess.CalledProcessError(1,'ps')]:
            with patch.object(o,'snapshot',side_effect=error),patch.object(o,'run_sampler') as run:self.execute();run.assert_not_called()
            self.assertEqual(self.read()['status'],'inconclusive')
    def test_sample_timeout_nonzero_and_foreign_output(self):
        for effect in [subprocess.TimeoutExpired('sample',5),lambda *a,**k:1,lambda *a,**k:0]:
            with patch.object(o,'snapshot',return_value='owned'),patch.object(o,'run_sampler',side_effect=effect):self.execute()
            self.assertEqual(self.read()['status'],'inconclusive')
    def test_snapshot_binds_pid_parent_executable_and_zombie(self):
        for text in [f'42 {os.getpid()} S /usr/bin/xcodebuild',f'43 {os.getpid()} S xcodebuild',f'42 1 S xcodebuild',f'42 {os.getpid()} Z xcodebuild',f'42 {os.getpid()} S other']:
            with patch.object(o.subprocess,'check_output',return_value=text):
                if text.startswith(f'42 {os.getpid()} S /'):self.assertEqual(o.snapshot(42,time.monotonic()+5),text)
                else:self.assertRaises(ValueError,o.snapshot,42,time.monotonic()+5)
    def test_forward_preserves_bytes_exit_missing_trigger_and_broken_stdout(self):
        for code in [0,65]:
            process=subprocess.Popen([sys.executable,'-c',f'import os;os.write(1,b"abc\\x00def\\n");raise SystemExit({code})'],stdout=subprocess.PIPE)
            with patch.object(o.os,'write',side_effect=BrokenPipeError):
                self.assertEqual(o.forward(process,self.launch,self.path)[0],code)
            self.assertEqual((self.path/'stdout.raw').read_bytes(),b'abc\x00def\n')
            self.assertTrue(json.loads((self.path/'stdout-receipt.json').read_text())['downstream_broken'])
            self.assertEqual(self.read()['status'],'inconclusive')
    def test_stuck_observer_killed_and_child_exit_retained(self):
        # Replace only worker creation with a deliberately stuck owned process.
        process=subprocess.Popen([sys.executable,'-c','import os;os.write(1,'+repr(LINE+LINE+b'end\n')+');raise SystemExit(65)'],stdout=subprocess.PIPE)
        original=o.subprocess.Popen
        workers=[]
        def stuck(*args,**kwargs):
            script='import subprocess,sys,time,pathlib; p=subprocess.Popen([sys.executable,"-c","import time;time.sleep(60)"]);pathlib.Path('+repr(str(self.path/'synthetic-sampler.pid'))+').write_text(str(p.pid));time.sleep(60)'
            worker=original([sys.executable,'-c',script],start_new_session=True)
            workers.append(worker);return worker
        start=time.monotonic()
        worker=stuck()
        prepared=Mock(worker=worker,record={'idle_deadline_monotonic_ns':o.monotonic_ns()+30_000_000_000},channel=Mock(),log=None)
        with patch.object(o.os,'write',side_effect=lambda fd,b:len(b)):
            code,report=o.forward(process,self.launch,self.path,prepared)
        self.assertEqual(code,65);self.assertEqual(len(workers),1)
        self.assertLess(time.monotonic()-start,5)
        self.assertIsNotNone(workers[0].returncode)
        child=int((self.path/'synthetic-sampler.pid').read_text())
        state=subprocess.run(['/bin/ps','-p',str(child),'-o','stat='],text=True,capture_output=True).stdout.strip()
        self.assertTrue(not state or state.startswith('Z'),state)
        self.assertTrue(report['worker_termination']['reaped'])
        self.assertEqual(report['worker_termination']['signal_result'],'sent')
        self.assertEqual((self.path/'stdout.raw').read_bytes(),LINE+LINE+b'end\n')
        self.assertEqual(self.read()['status'],'inconclusive')
    def test_read_error_fallback_preserves_running_child_result(self):
        process=subprocess.Popen([sys.executable,'-c','import os,time;os.write(1,b"abc");time.sleep(.15);os.write(1,b"def");raise SystemExit(65)'],stdout=subprocess.PIPE)
        with patch.object(o.os,'read',side_effect=OSError('injected')),patch.object(o.os,'write',side_effect=lambda fd,b:len(b)):
            code,report=o.forward(process,self.launch,self.path)
        self.assertEqual(code,65);self.assertEqual((self.path/'stdout.raw').read_bytes(),b'abcdef')
        self.assertTrue(any(e['operation']=='stream-read' for e in report['errors']))
    def test_raw_open_write_flush_and_receipt_errors_keep_child_result(self):
        original_open=Path.open
        for operation in ('open','write','flush','receipt'):
            process=subprocess.Popen([sys.executable,'-c','import os,time;os.write(1,b"abc");time.sleep(.1);os.write(1,b"def");raise SystemExit(65)'],stdout=subprocess.PIPE)
            def failing_open(path,*args,**kwargs):
                if path.name=='stdout.raw':
                    if operation=='open':raise OSError('raw open injected')
                    if operation in ('write','flush'):
                        wrapper=Mock(wraps=original_open(path,*args,**kwargs))
                        getattr(wrapper,operation).side_effect=OSError(operation+' injected')
                        return wrapper
                return original_open(path,*args,**kwargs)
            with patch.object(Path,'open',failing_open),patch.object(o.os,'write',side_effect=lambda fd,b:len(b)):
                if operation=='receipt':
                    with patch.object(o,'write',side_effect=OSError('receipt injected')):code,report=o.forward(process,self.launch,self.path)
                else:code,report=o.forward(process,self.launch,self.path)
            self.assertEqual(code,65,operation);self.assertEqual(report['bytes'],6)
            self.assertTrue(report['errors'],operation)

if __name__=='__main__':unittest.main()

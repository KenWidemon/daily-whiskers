"""Fresh-interpreter private IPC tests. All process inspection/sampling stubbed."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock,patch
import launch_observation as o

LINE=b'    t = 1.00s Launch com.example.kenwidemon.dailywhiskers\n'
RAW=b'prefix\x00\xff\n'+LINE+LINE+b'tail\x00\xfe\n'
SOURCE=Path(o.__file__).resolve()


def fixture(root, mode='success'):
    directory=root/'evidence';directory.mkdir()
    scripts=root/'fixture';scripts.mkdir()
    shutil.copyfile(SOURCE.with_name('launch_capture_bootstrap.py'),scripts/'launch_capture_bootstrap.py')
    shim='''import importlib.util,json,os,pathlib,sys,time
spec=importlib.util.spec_from_file_location('real_observer',SOURCE)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
m.__file__=__file__
source_identity=m.source_identity
send_once=m.send_once
receive_frame=m.receive_frame
PATTERN=m.PATTERN
CLOCK_DOMAIN=m.CLOCK_DOMAIN
m.snapshot=lambda *a: 'SYNTHETIC identity only'
original=m.run_sampler
def sampler(command,output,until,path):
    body='Process: xcodebuild ['+command[1]+']\\nSYNTHETIC STACK ONLY\\n'
    stub=[sys.executable,'-B','-c','from pathlib import Path;Path('+repr(command[-1])+').write_text('+repr(body)+')']
    result=original(stub,output,until,path)
    record=json.loads(path.read_text());record['command']=command;record['synthetic_only']=True;m.write(path,record)
    return result
m.run_sampler=sampler
observe=m.observe
'''.replace('SOURCE',repr(str(SOURCE)))
    if mode=='import-failure':shim="raise ImportError('synthetic import failure')\n"
    if mode=='import-stuck':shim='import time;time.sleep(30)\n'+shim
    if mode=='stuck':shim+='\ndef observe(*args):\n print("synthetic stuck",file=sys.stderr,flush=True)\n time.sleep(30)\n'
    if mode=='persistence':shim+='\ndef fail(*args,**kwargs): raise OSError("ready persist injected")\npathlib.Path.write_text=fail\n'
    if mode=='capture-persistence':shim+='\ndef observe(*args):\n def fail(*a,**k): raise OSError("final persist injected")\n pathlib.Path.write_text=fail\n raise OSError("capture persist injected")\n'
    (scripts/'launch_observation.py').write_text(shim)
    return directory,scripts


class Prestarted(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
    def prepare(self,mode='success',budget=20):
        self.directory,self.scripts=fixture(self.root,mode)
        self.filepatch=patch.object(o,'__file__',str(self.scripts/'launch_observation.py'));self.filepatch.start();self.addCleanup(self.filepatch.stop)
        self.context={'source_sha':'a'*40,'run_id':'1','run_attempt':'1','stage':'cards-largest',
            'parent_pid':os.getpid(),'deadline':time.time()+budget,'command':['xcodebuild','SYNTHETIC-NOT-EXECUTED']}
        prepared=o.PreparedObserver(self.context,self.directory)
        self.addCleanup(lambda:prepared.close('test-cleanup') if prepared.worker is not None else None)
        return prepared
    def child(self,raw=RAW):
        started=time.time()
        child=subprocess.Popen([sys.executable,'-B','-c','import os;os.write(1,'+repr(raw)+');raise SystemExit(65)'],stdout=subprocess.PIPE,close_fds=True)
        launch=dict(self.context,pid=child.pid,started=started)
        return child,launch
    def trigger(self,prepared,launch,**updates):
        received={'clock_domain':o.CLOCK_DOMAIN,'wall_time':time.time(),'monotonic_ns':o.monotonic_ns()}
        until=min(received['monotonic_ns']+4_000_000_000,prepared.record['idle_deadline_monotonic_ns'])
        launch.update(observer_preparation=prepared.record,observer_deadline_monotonic_ns=until)
        frame={'kind':'trigger','preparation':prepared.record,'worker_pid':prepared.worker.pid,'launch':launch,
               'line':LINE.decode().rstrip(),'received':received,'deadline_monotonic_ns':until}
        frame.update(updates)
        return frame
    def test_ready_before_child_full_path_raw_exit_and_clean_completion(self):
        prepared=self.prepare();child,launch=self.child()
        self.assertLessEqual(prepared.ready['ready_wall'],launch['started'])
        with patch.object(o.os,'write',side_effect=lambda fd,data:len(data)):
            code,report=o.forward(child,launch,self.directory,prepared)
        self.assertEqual(code,65);self.assertEqual((self.directory/'stdout.raw').read_bytes(),RAW)
        self.assertFalse(report['errors']);self.assertEqual(report['observer'],'reaped',report)
        self.assertEqual(report['worker_termination']['signal_result'],'not-needed')
        self.assertEqual(report['worker_termination']['worker_exit_code'],0)
        self.assertEqual(report['sha256'],hashlib.sha256(RAW).hexdigest())
        self.assertTrue(json.loads((self.directory/'sampler-lifecycle.json').read_text())['reaped'])
    def test_import_failure_no_ready_no_child(self):
        with self.assertRaises((EOFError,OSError,ValueError)):self.prepare('import-failure')
        self.assertIn('synthetic import failure',(self.directory/'observer-stderr.log').read_text())
        self.assertFalse((self.directory/'observer-ready.json').exists())
        self.assertTrue(json.loads((self.directory/'observer-abandonment.json').read_text())['termination']['reaped'])
    def test_import_stuck_bounded_startup(self):
        start=time.monotonic()
        with self.assertRaises((EOFError,OSError,ValueError)):self.prepare('import-stuck')
        self.assertLess(time.monotonic()-start,4.8)
        self.assertFalse((self.directory/'sampler-lifecycle.json').exists())
    def test_ready_persistence_failure_prevents_ready(self):
        with self.assertRaises((EOFError,OSError,ValueError)):self.prepare('persistence')
        self.assertIn('ready persist injected',(self.directory/'observer-stderr.log').read_text())
        self.assertFalse((self.directory/'observer-ready.json').exists())
    def test_stuck_capture_original_deadline_and_selected_exit(self):
        prepared=self.prepare('stuck');child,launch=self.child()
        start=time.monotonic()
        with patch.object(o.os,'write',side_effect=lambda fd,data:len(data)):
            code,report=o.forward(child,launch,self.directory,prepared)
        self.assertEqual(code,65);self.assertLess(time.monotonic()-start,4.8)
        self.assertTrue(report['worker_termination']['reaped']);self.assertEqual(report['worker_termination']['worker_exit_code'],-9)
        self.assertEqual((self.directory/'stdout.raw').read_bytes(),RAW)
    def test_missing_trigger_never_samples_and_cleans(self):
        prepared=self.prepare();child,launch=self.child(b'no trigger\x00\xff')
        with patch.object(o.os,'write',side_effect=lambda fd,data:len(data)):
            code,report=o.forward(child,launch,self.directory,prepared)
        self.assertEqual(code,65);self.assertFalse((self.directory/'sampler-lifecycle.json').exists())
        self.assertTrue(report['worker_termination']['reaped'])
    def test_idle_eof_exits_promptly_without_sample(self):
        prepared=self.prepare();prepared.channel.close();prepared.channel=None
        self.assertEqual(prepared.worker.wait(timeout=1),1)
        self.assertFalse((self.directory/'sampler-lifecycle.json').exists())
    def test_idle_budget_expires_without_sample(self):
        prepared=self.prepare(budget=.5)
        code=prepared.worker.wait(timeout=1)
        self.assertIn(code,(1,-9))
        if code==1:self.assertEqual(json.loads((self.directory/'observer-bootstrap.json').read_text())['status'],'error')
        self.assertFalse((self.directory/'sampler-lifecycle.json').exists())
    def test_partial_frame_eof_and_oversize_rejected(self):
        prepared=self.prepare();prepared.channel.send(b'{');prepared.channel.shutdown(socket.SHUT_WR)
        self.assertEqual(prepared.worker.wait(timeout=1),1)
        self.assertFalse((self.directory/'sampler-lifecycle.json').exists())
    def test_partial_frame_lifetime_bounded(self):
        prepared=self.prepare();prepared.channel.send(b'{')
        start=time.monotonic();self.assertEqual(prepared.worker.wait(timeout=4.8),1)
        self.assertLess(time.monotonic()-start,4.8)
    def test_expired_or_foreign_frame_fails_without_sample(self):
        prepared=self.prepare();launch=dict(self.context,pid=123,started=time.time())
        frame=self.trigger(prepared,launch,worker_pid=prepared.worker.pid+1)
        o.send_once(prepared.channel,frame)
        self.assertEqual(prepared.worker.wait(timeout=1),1)
        self.assertFalse((self.directory/'sampler-lifecycle.json').exists())
    def test_duplicate_during_capture_forces_group_cleanup(self):
        prepared=self.prepare('stuck');child,launch=self.child(b'')
        try:
            o.send_once(prepared.channel,self.trigger(prepared,launch))
            prepared.channel.send(b'duplicate\n')
            self.assertIn(prepared.worker.wait(timeout=1),(1,-9))
        finally:child.wait();child.stdout.close()
    def test_eof_during_capture_forces_group_cleanup(self):
        prepared=self.prepare('stuck');child,launch=self.child(b'')
        try:
            o.send_once(prepared.channel,self.trigger(prepared,launch))
            prepared.channel.shutdown(socket.SHUT_WR)
            self.assertEqual(prepared.worker.wait(timeout=1),-9)
        finally:child.wait();child.stdout.close()
    def test_actual_parent_exit_closes_private_endpoint_not_inherited_by_child(self):
        directory,scripts=fixture(self.root)
        program=r"""import json,os,pathlib,subprocess,sys,time
sys.path.insert(0,SOURCE_DIR)
import launch_observation as o
o.__file__=FIXTURE
context={'deadline':time.time()+20,'command':['xcodebuild'],'parent_pid':os.getpid()}
p=o.PreparedObserver(context,pathlib.Path(DIRECTORY))
fd=p.channel.fileno();inode=os.fstat(fd).st_ino
check='import os; fd='+str(fd)+'; inode='+str(inode)+'\ntry: assert os.fstat(fd).st_ino!=inode\nexcept OSError: pass'
subprocess.run([sys.executable,'-B','-c',check],close_fds=True,check=True)
print(json.dumps({'worker':p.worker.pid,'fd_closed_in_child':True}),flush=True)
os._exit(0)
""".replace('SOURCE_DIR',repr(str(SOURCE.parent))).replace('FIXTURE',repr(str(scripts/'launch_observation.py'))).replace('DIRECTORY',repr(str(directory)))
        parent=subprocess.run([sys.executable,'-B','-c',program],capture_output=True,text=True,timeout=5)
        self.assertEqual(parent.returncode,0,parent.stderr)
        identity=json.loads(parent.stdout);self.assertTrue(identity['fd_closed_in_child'])
        # One owned-PID check after the worker's explicit EOF cleanup reserve.
        time.sleep(.8)
        state=subprocess.run(['/bin/ps','-p',str(identity['worker']),'-o','stat='],capture_output=True,text=True).stdout.strip()
        self.assertTrue(not state or state.startswith('Z'),state)
        record=json.loads((directory/'observer-bootstrap.json').read_text())
        self.assertEqual(record['status'],'error');self.assertEqual(record['errors'][0]['type'],'EOFError')
        self.assertFalse((directory/'sampler-lifecycle.json').exists())
    def test_shared_clock_fresh_interpreter_bracket_and_missing_clock(self):
        before=o.monotonic_ns()
        child=subprocess.check_output([sys.executable,'-B','-c','import time;print(time.clock_gettime_ns(time.CLOCK_UPTIME_RAW))'],text=True)
        after=o.monotonic_ns();self.assertLessEqual(before,int(child));self.assertLessEqual(int(child),after)
        with patch.object(o.sys,'platform','unavailable'):
            with self.assertRaisesRegex(RuntimeError,'Shared Darwin'):o.monotonic_ns()
    def test_expired_malformed_wrong_domain_frames(self):
        # Each rejection uses a fresh worker; no retry of a one-shot trigger.
        for mutation in ('expired','malformed','domain','nonce'):
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as temp:
                oldroot=self.root;self.root=Path(temp)
                try:
                    prepared=self.prepare();launch=dict(self.context,pid=123,started=time.time())
                    frame=self.trigger(prepared,launch)
                    if mutation=='expired':frame['deadline_monotonic_ns']=o.monotonic_ns()-1
                    elif mutation=='malformed':frame['deadline_monotonic_ns']='not-integer'
                    else:
                        frame['preparation']=dict(frame['preparation'])
                        frame['preparation']['clock_domain' if mutation=='domain' else 'nonce']='foreign'
                    o.send_once(prepared.channel,frame)
                    self.assertEqual(prepared.worker.wait(timeout=1),1)
                    self.assertFalse((self.directory/'sampler-lifecycle.json').exists())
                    prepared.close('negative-test-finished')
                finally:self.root=oldroot;self.filepatch.stop()
    def test_single_send_eagain_partial_oversize_no_retry(self):
        for result in (BlockingIOError('EAGAIN'),2):
            channel=Mock()
            if isinstance(result,Exception):channel.send.side_effect=result
            else:channel.send.return_value=result
            with self.assertRaises(OSError):o.send_once(channel,{'kind':'trigger'})
            channel.send.assert_called_once();channel.setblocking.assert_called_once_with(False)
        channel=Mock()
        with self.assertRaises(ValueError):o.send_once(channel,{'x':'x'*o.FRAME_LIMIT})
        channel.send.assert_not_called()
    def test_late_trigger_after_expiry_preserves_child_exit(self):
        for reaped in (True,False):
            with self.subTest(reaped=reaped):
                directory=self.root/str(reaped);directory.mkdir()
                child=subprocess.Popen([sys.executable,'-B','-c',
                    'import os,time;time.sleep(.05);os.write(1,'+repr(RAW)+');raise SystemExit(65)'],stdout=subprocess.PIPE)
                worker=Mock(pid=42)
                channel=Mock();channel.close.side_effect=OSError('late close injected')
                prepared=Mock(worker=worker,record={'idle_deadline_monotonic_ns':o.monotonic_ns()-1},channel=channel,log=None)
                with patch.object(o,'stop_worker',return_value={'reaped':reaped,'signal_result':'sent' if reaped else 'unverified'}),patch.object(o.os,'write',side_effect=lambda fd,data:len(data)):
                    code,report=o.forward(child,{'pid':child.pid,'deadline':time.time()+10},directory,prepared)
                self.assertEqual(code,65);self.assertEqual(child.returncode,65)
                self.assertEqual((directory/'stdout.raw').read_bytes(),RAW)
                prepared.trigger.assert_not_called()
                self.assertEqual({e['operation'] for e in report['errors']},{'worker-trigger','trigger-channel-close'})

    def test_prepared_close_errors_preserve_actual_exit_and_raw_bytes(self):
        for failing in ('channel','log','both'):
            with self.subTest(failing=failing),tempfile.TemporaryDirectory() as temp:
                directory=Path(temp)
                raw=b'synthetic close failure\x00\xff'
                child=subprocess.Popen([sys.executable,'-B','-c',
                    'import os,time;os.write(1,'+repr(raw)+');time.sleep(.05);raise SystemExit(65)'],
                    stdout=subprocess.PIPE,close_fds=True)
                channel=Mock();log=Mock()
                if failing in ('channel','both'):channel.close.side_effect=OSError('channel close injected')
                if failing in ('log','both'):log.close.side_effect=OSError('log close injected')
                prepared=Mock(worker=None,channel=channel,log=log,
                    record={'idle_deadline_monotonic_ns':o.monotonic_ns()+20_000_000_000})
                launch={'pid':child.pid,'command':['xcodebuild'],'deadline':time.time()+20}
                with patch.object(o.os,'write',side_effect=lambda fd,data:len(data)):
                    code,report=o.forward(child,launch,directory,prepared)
                self.assertEqual(code,65);self.assertEqual(child.returncode,65)
                self.assertEqual(report['selected_child_exit'],65)
                self.assertEqual((directory/'stdout.raw').read_bytes(),raw)
                self.assertEqual(report['sha256'],hashlib.sha256(raw).hexdigest())
                operations={row['operation'] for row in report['errors']}
                for name in ('channel','log'):
                    self.assertEqual('prepared-'+name+'-close' in operations,failing in (name,'both'))
                channel.close.assert_called_once();log.close.assert_called_once()
                self.assertIsNone(prepared.channel);self.assertIsNone(prepared.log)
                self.assertEqual(json.loads((directory/'stdout-receipt.json').read_text())['selected_child_exit'],65)

    def test_capture_persistence_failure_keeps_raw_child_exit(self):
        prepared=self.prepare('capture-persistence');child,launch=self.child()
        with patch.object(o.os,'write',side_effect=lambda fd,data:len(data)):
            code,report=o.forward(child,launch,self.directory,prepared)
        self.assertEqual(code,65);self.assertEqual((self.directory/'stdout.raw').read_bytes(),RAW)
        self.assertNotEqual(report['observer'],'reaped');self.assertIn('persist injected',(self.directory/'observer-stderr.log').read_text())

if __name__=='__main__':unittest.main()

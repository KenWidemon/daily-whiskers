import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import Mock,patch
import launch_observation as o

class Completion(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.worker=Mock(pid=42,returncode=None)
        now=time.time();self.launch={'pid':12,'command':['xcodebuild'],'started':now-10,'deadline':now+100,'source_sha':'a'*40,'run_id':'1'}
        self.command=['/usr/bin/sample','12','1','10','-file',str(self.root/'host-xcodebuild.sample.txt')]
        raw=b'Process: xcodebuild [12]\nfixture stack'
        (self.root/'host-xcodebuild.sample.txt').write_bytes(raw)
        self.records={
          'observer-bootstrap.json':{'schema':'observer-bootstrap-v1','status':'returned','pid':42,'group':42,'parent_pid':os.getpid(),'identity':self.launch,'errors':[],'started':now-3,'imported':now-2.9,'finished':now-.1},
          'host-observation.json':{'schema':o.SCHEMA,'status':'captured-unqualified','pid':12,'command':['xcodebuild'],'identity':{k:v for k,v in self.launch.items() if k!='command'},'sample_command':self.command,'sample_exit':0,'started':now-2.8,'finished':now-.2,'elapsed_seconds':2.6,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()},
          'sampler-lifecycle.json':{'schema':'sampler-lifecycle-v1','status':'returned','pid':43,'parent_pid':42,'group':42,'command':self.command,'exit_code':0,'reaped':True,'started':now-2.7,'finished':now-.3}}
        self.persist()
    def persist(self):
        for name,record in self.records.items():(self.root/name).write_text(json.dumps(record))
    def test_clean_success_does_not_signal(self):
        self.worker.wait.return_value=0
        with patch.object(o,'stop_worker') as stop:
            r=o.finish_worker(self.worker,self.launch,self.root)
        stop.assert_not_called();self.worker.wait.assert_called_once_with(timeout=0)
        self.assertEqual(r['signal_result'],'not-needed');self.assertTrue(r['reaped'])
    def test_missing_malformed_stale_failed_pending_receipts_do_not_skip_cleanup(self):
        mutations=[('observer-bootstrap.json','status','error'),('observer-bootstrap.json','pid',99),('observer-bootstrap.json','identity',{}),('sampler-lifecycle.json','reaped',False),('sampler-lifecycle.json','exit_code',1),('sampler-lifecycle.json','parent_pid',99),('sampler-lifecycle.json','signal_error','denied'),('host-observation.json','sha256','bad')]
        original=copy.deepcopy(self.records)
        for name,key,value in mutations:
            with self.subTest(name=name,key=key):
                self.records=copy.deepcopy(original);self.records[name][key]=value;self.persist()
                with patch.object(o,'stop_worker',return_value={'reaped':True,'signal_result':'sent'}) as stop:
                    r=o.finish_worker(self.worker,self.launch,self.root)
                stop.assert_called_once();self.worker.wait.assert_not_called();self.assertEqual(r['completion_proof'],'invalid-or-missing')
        for raw in ('not json','{}'):
            (self.root/'observer-bootstrap.json').write_text(raw)
            with patch.object(o,'stop_worker',return_value={}) as stop:o.finish_worker(self.worker,self.launch,self.root)
            stop.assert_called_once()
        (self.root/'observer-bootstrap.json').unlink()
        with patch.object(o,'stop_worker',return_value={}) as stop:o.finish_worker(self.worker,self.launch,self.root)
        stop.assert_called_once()
    def test_valid_receipts_but_worker_running_escalates_once(self):
        self.worker.wait.side_effect=subprocess.TimeoutExpired('worker',0)
        with patch.object(o,'stop_worker',return_value={'reaped':True,'signal_result':'sent'}) as stop:r=o.finish_worker(self.worker,self.launch,self.root)
        stop.assert_called_once();self.assertEqual(r['completion_proof'],'worker-still-running')
    def test_crash_after_receipt_does_not_signal_reused_group(self):
        def reap(**kwargs):self.worker.returncode=-9;return -9
        self.worker.wait.side_effect=reap
        with patch.object(o,'stop_worker') as stop:r=o.finish_worker(self.worker,self.launch,self.root)
        stop.assert_not_called();self.assertEqual(r['signal_result'],'unverified')
    def test_already_reaped_never_signals(self):
        self.worker.returncode=0
        with patch.object(o,'stop_worker') as stop:r=o.finish_worker(self.worker,self.launch,self.root)
        stop.assert_not_called();self.worker.wait.assert_not_called();self.assertEqual(r['signal_result'],'unverified')
    def test_wait_error_never_signals_uncertain_pid(self):
        self.worker.wait.side_effect=OSError('wait uncertain')
        with patch.object(o,'stop_worker') as stop:r=o.finish_worker(self.worker,self.launch,self.root)
        stop.assert_not_called();self.assertEqual(r['signal_result'],'unverified')
    def test_invalid_receipt_and_signal_denial_remains_uncertain(self):
        (self.root/'observer-bootstrap.json').unlink();self.worker.wait.return_value=-9
        with patch.object(o.os,'killpg',side_effect=PermissionError('denied')):r=o.finish_worker(self.worker,self.launch,self.root)
        self.assertTrue(r['reaped']);self.assertEqual(r['signal_result'],'unverified');self.assertEqual(r['completion_proof'],'invalid-or-missing')
if __name__=='__main__':unittest.main()

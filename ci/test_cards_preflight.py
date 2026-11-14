"""Execute actual preflight with synthetic files, never a simulator or build."""
import json
import os
from pathlib import Path
import re
import tempfile
import time
import unittest
from unittest.mock import patch
import diagnostic as d
import diagnostic_postrun as postrun
import simulator
ROOT=Path(__file__).resolve().parent.parent
REF='refs/heads/codex/ci-cards-focused-20261114'
UUID='11111111-1111-4111-8111-111111111111'
class Preflight(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory();self.addCleanup(tmp.cleanup)
        self.build=Path(tmp.name)/'build';self.build.mkdir();self.out=self.build/'diagnostic'
        deadline=time.time()+2700
        self.env={'SOURCE_SHA':'a'*40,'TESTED_SHA':'a'*40,'GITHUB_SHA':'a'*40,'GITHUB_RUN_ID':'123',
            'GITHUB_RUN_ATTEMPT':'1','GITHUB_JOB':'diagnostic','CI_SHARD_ID':'cards','CI_DIAGNOSTIC_LANE':'cards',
            'GITHUB_EVENT_NAME':'workflow_dispatch','GITHUB_REF':REF,'CI_EXECUTION_DEADLINE':str(deadline),'SIMULATOR_ID':UUID}
        identity={'source_sha':'a'*40,'tested_sha':'a'*40,'run_id':'123','run_attempt':'1','job':'diagnostic','shard':'cards'}
        self.budget=identity|{'started':deadline-2700,'deadline':deadline,'execution_seconds':2700}
        self.owned=identity|{'status':'ready','readback_verified':True,'ownership':'created','simulator_id':UUID,
            'preexisting_ids':[],'runtime':simulator.RUNTIME,'version':simulator.VERSION,'build':simulator.BUILD,
            'architecture':'arm64','name':simulator.NAME,'device_type':simulator.DEVICE_TYPE}
    def invoke(self,changes=None,missing=(),clock_error=None):
        env=self.env|dict(changes or {})
        for key in missing:env.pop(key,None)
        (self.build/'job-budget.json').write_text(json.dumps(self.budget))
        (self.build/'simulator.json').write_text(json.dumps(self.owned))
        with patch.dict(os.environ,env,clear=True),patch.object(d,'BUILD',self.build),patch.object(d,'DIAGNOSTIC',self.out),patch.object(postrun,'marker_uptime_ns',return_value=123456,side_effect=clock_error),patch.object(d.subprocess,'Popen',side_effect=AssertionError('No external tool allowed')):
            d.preflight()
        return json.loads((self.out/'preflight.json').read_text())
    def test_actual_preflight_accepts_intended_dispatch_context(self):
        r=self.invoke();self.assertEqual(r['status'],'success');self.assertEqual(r['source_sha'],'a'*40)
        self.assertEqual(r['host_uptime_probe_ns'],123456);self.assertEqual(r['cache_restore'],'disabled');self.assertFalse(r['cold_control_certified'])
    def test_workflow_guard_context_is_executed(self):
        text=(ROOT/'.github/workflows/ios.yml').read_text()
        match=re.search(r"^    if: github.ref == '([^']+)' && github.run_attempt == (\d+)\s*$",text,re.M)
        self.assertIsNotNone(match);self.assertEqual(match[1],REF);self.assertEqual(match[2],'1')
        self.assertIn('  workflow_dispatch:',text);self.assertNotIn('  push:',text);self.assertNotIn('  pull_request:',text)
        r=self.invoke({'GITHUB_REF':match[1],'GITHUB_RUN_ATTEMPT':match[2]});self.assertEqual(r['status'],'success')
    def test_old_wrong_branch_rejected(self):
        for value in ('refs/heads/codex/ci-launch-discriminator-20261114','refs/heads/main','refs/tags/ci-cards-focused-20261114'):
            with self.subTest(value=value):self.assertRaisesRegex(ValueError,'Only one initial',self.invoke,{'GITHUB_REF':value})
    def test_wrong_event_rejected(self):
        for value in ('push','pull_request','schedule',''):
            with self.subTest(value=value):self.assertRaises(ValueError,self.invoke,{'GITHUB_EVENT_NAME':value})
    def test_wrong_or_malformed_attempt_rejected(self):
        for value in ('0','2','01','x',''):
            with self.subTest(value=value):self.assertRaises(ValueError,self.invoke,{'GITHUB_RUN_ATTEMPT':value})
    def test_missing_context_rejected(self):
        for key in self.env:
            with self.subTest(key=key):self.assertRaises((ValueError,KeyError),self.invoke,missing=(key,))
    def test_source_run_lane_job_identity_rejected(self):
        for key,value in [('SOURCE_SHA','b'*40),('TESTED_SHA','b'*40),('GITHUB_SHA','b'*40),('SOURCE_SHA','bad'),('GITHUB_RUN_ID','x'),('GITHUB_JOB','harness'),('CI_SHARD_ID','startup'),('CI_DIAGNOSTIC_LANE','invalid')]:
            with self.subTest(key=key):self.assertRaises(ValueError,self.invoke,{key:value})
    def test_malformed_source_even_when_all_shas_match_rejected(self):
        self.assertRaises(ValueError,self.invoke,{k:'bad' for k in ('SOURCE_SHA','TESTED_SHA','GITHUB_SHA')})
    def test_budget_gate_preserved(self):
        self.budget['execution_seconds']=3000;self.assertRaises(ValueError,self.invoke)
    def test_ownership_gate_preserved(self):
        self.owned['ownership']='reused';self.assertRaises(ValueError,self.invoke)
    def test_preexisting_destination_gate_preserved(self):
        self.owned['preexisting_ids']=[UUID];self.assertRaises(ValueError,self.invoke)
    def test_uncached_gate_preserved(self):
        (self.build/'SourcePackages').mkdir();self.assertRaises(ValueError,self.invoke)
    def test_clock_failure_still_blocks(self):
        self.assertRaises(ValueError,self.invoke,clock_error=ValueError('unsupported clock'))
if __name__=='__main__':unittest.main()

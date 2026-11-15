"""Offline contract tests. Never invoke Xcode/app/simulator/network operations."""
import ast
import copy
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('boundary',Path(__file__).with_name('reminder_boundary.py'))
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
REPO = Path(__file__).resolve().parents[1]

class Contract(unittest.TestCase):
    def env(self):
        return {'GITHUB_REPOSITORY':b.REPOSITORY,'GITHUB_EVENT_NAME':'workflow_dispatch',
                'GITHUB_REF':b.REF,'GITHUB_RUN_ATTEMPT':'1','RUNNER_ARCH':'ARM64',
                'GITHUB_SHA':'a'*40,'APPROVED_SHA':'a'*40,'GITHUB_RUN_ID':'123','GITHUB_JOB':'reminder-boundary'}
    @classmethod
    def setUpClass(cls):
        # Psych YAML 1.1 maps unquoted `on` to true. Normalize that parser behavior,
        # not a regex/text approximation of the workflow. actionlint is separate.
        cls.workflow=json.loads(subprocess.check_output(['ruby','-rpsych','-rjson','-e',
            'puts JSON.generate(Psych.load_file(ARGV[0]))',str(REPO/'.github/workflows/ios.yml')]))
        cls.job=cls.workflow['jobs']['reminder-boundary']
    def test_identity_exact(self):
        self.assertEqual(b.identity(self.env())['APPROVED_SHA'],'a'*40)
    def test_identity_negative_each_field(self):
        for key in self.env():
            for value in ('','wrong','2' if key=='GITHUB_RUN_ATTEMPT' else 'untrusted'):
                e=self.env();e[key]=value
                with self.subTest(key=key,value=value),self.assertRaises(b.Invalid): b.identity(e)
    def test_identity_mismatched_hash(self):
        e=self.env();e['GITHUB_SHA']='b'*40
        with self.assertRaises(b.Invalid):b.identity(e)
    def test_parsed_workflow_shape(self):
        self.assertEqual(set(self.workflow.get('on',self.workflow.get('true'))),{'workflow_dispatch'})
        self.assertEqual(set(self.workflow['jobs']),{'reminder-boundary'})
        self.assertEqual(self.workflow['permissions'],{'contents':'read'})
        self.assertEqual(self.job['runs-on'],'xcode-27')
        self.assertEqual(self.job['timeout-minutes'],60)
        self.assertNotIn('strategy',self.job)
        self.assertNotIn('CI Gate',self.job['name'])
        inputs=self.workflow.get('on',self.workflow.get('true'))['workflow_dispatch']['inputs']
        self.assertEqual(inputs['cache_epoch']['default'],'v2')
        self.assertEqual(inputs['cache_epoch']['type'],'string')
        self.assertTrue(inputs['approved_sha']['required'])
    def test_parsed_pinned_actions_and_budget_order(self):
        steps=self.job['steps']
        self.assertIn('started_monotonic',steps[0]['run'])
        self.assertEqual(steps[1]['uses'],'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1')
        self.assertEqual(steps[1]['with']['ref'],'${{ github.sha }}')
        self.assertFalse(steps[1]['with']['persist-credentials'])
        self.assertEqual(steps[1]['timeout-minutes'],3)
        self.assertEqual(steps[-1]['uses'],'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a')
        self.assertEqual(steps[-1]['timeout-minutes'],5)
        self.assertEqual(steps[-1]['with']['retention-days'],30)
        self.assertEqual(steps[-1]['with']['compression-level'],0)
        self.assertFalse(steps[-1]['with']['overwrite'])
        self.assertEqual([s['uses'] for s in steps if 'uses' in s], [steps[1]['uses'],steps[-1]['uses']])
    def guard(self, env, root):
        script=self.job['steps'][0]['run'].split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]
        env=dict(env,RUNNER_TEMP=str(root))
        with patch.dict(os.environ,env,clear=True): exec(compile(script,'actual-workflow-guard','exec'),{})
    def test_actual_workflow_guard(self):
        with tempfile.TemporaryDirectory() as d:
            self.guard(self.env(),Path(d))
            receipt=json.loads((Path(d)/'reminder-boundary/budget.json').read_text())
            self.assertEqual(receipt['sha'],'a'*40)
            with self.assertRaises(FileExistsError):self.guard(self.env(),Path(d))
    def test_actual_workflow_rejects_wrong_event_ref_attempt_sha(self):
        for key,value in [('GITHUB_EVENT_NAME','push'),('GITHUB_REF','refs/heads/codex/develop'),('GITHUB_RUN_ATTEMPT','2'),('GITHUB_REPOSITORY','other/repo'),('APPROVED_SHA','b'*40),('RUNNER_ARCH','X64')]:
            with self.subTest(key=key),tempfile.TemporaryDirectory() as d:
                e=self.env();e[key]=value
                with self.assertRaises(SystemExit):self.guard(e,Path(d))
                self.assertFalse((Path(d)/'reminder-boundary').exists())
    def test_budget_never_resets(self):
        now=[100.]
        budget=b.Budget(100,clock=lambda:now[0])
        self.assertEqual(budget.allowance(9999),2625)
        now[0]=2600
        self.assertEqual(budget.allowance(9999),125)
        now[0]=2725
        with self.assertRaises(b.Invalid):budget.allowance(1)
        self.assertEqual(budget.allowance(9999,final=True),600)
        now[0]=3325
        with self.assertRaises(b.Invalid):budget.allowance(1,final=True)
    def test_budget_invalid_origin(self):
        for value in (-1,101,-4000):
            with self.subTest(value=value),self.assertRaises(b.Invalid): b.Budget(value,clock=lambda:100)
    def test_single_command_contract(self):
        cmd=b.test_command(Path('/job/build'),Path('/job/evidence/one.xcresult'),'A-UUID')
        self.assertEqual(cmd[:2],['xcodebuild','test'])
        self.assertEqual([x for x in cmd if x.startswith('-only-testing:')],['-only-testing:'+b.SELECTOR])
        for x in cmd:
            self.assertNotRegex(x,r'^-(test-iterations|retry|run-tests-until|skip-testing|test-repetition)')
        for key,value in [('-parallel-testing-enabled','NO'),('-maximum-concurrent-test-simulator-destinations','1'),('-default-test-execution-time-allowance','720'),('-maximum-test-execution-time-allowance','720'),('-configuration','Debug'),('-scheme','DailyWhiskersInteraction')]:
            self.assertEqual(cmd[cmd.index(key)+1],value)
        self.assertIn('CODE_SIGNING_ALLOWED=NO',cmd)
        self.assertIn('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING DW_REMINDER_ENABLE_PROBE',cmd)
    def test_toolchain_negative(self):
        rt={'runtimes':[{'identifier':b.RUNTIME,'isAvailable':True,'version':'27.0','buildversion':'24A434'}]}
        b.toolchain('Xcode 27.2\nBuild version 27B52','27.2','arm64',rt)
        for x,s,a in [('Xcode 27.1\nBuild version 27B52','27.2','arm64'),('Xcode 27.2\nBuild version WRONG','27.2','arm64'),('Xcode 27.2\nBuild version 27B52','27.1','arm64'),('Xcode 27.2\nBuild version 27B52','27.2','x86_64')]:
            with self.assertRaises(b.Invalid):b.toolchain(x,s,a,rt)
        for field,value in [('isAvailable',False),('version','27.1'),('buildversion','wrong')]:
            changed=copy.deepcopy(rt);changed['runtimes'][0][field]=value
            with self.assertRaises(b.Invalid):b.toolchain('Xcode 27.2\nBuild version 27B52','27.2','arm64',changed)
    def test_owned_device_only(self):
        current={'new':{'name':'exact','deviceTypeIdentifier':b.TYPE,'runtime':b.RUNTIME}}
        self.assertTrue(b.owns('new','exact',{},current))
        self.assertFalse(b.owns('new','exact',{'new':{}},current))
        self.assertFalse(b.owns('new','wrong',{},current))
        self.assertFalse(b.owns(None,'exact',{},current))
        for field in ('deviceTypeIdentifier','runtime'):
            changed=copy.deepcopy(current);changed['new'][field]='wrong'
            self.assertFalse(b.owns('new','exact',{},changed))
    def test_stable_preserves_lifecycle_not_metadata_claim(self):
        a={'id':{'name':'n','state':'Shutdown','lastUsedAt':'old'}}
        c=copy.deepcopy(a);c['id']['lastUsedAt']='new'
        self.assertEqual(b.stable(a),b.stable(c))
        c['id']['state']='Booted';self.assertNotEqual(b.stable(a),b.stable(c))
    def test_actual_python_xcresult_timestamp(self):
        self.assertEqual(b.wall_datetime('2026-11-14T20:29:41.271-0500').isoformat(),'2026-11-14T20:29:41.271000-05:00')
    def test_syntax(self):
        ast.parse(Path(b.__file__).read_text())
    def test_fake_only_and_no_normal_helper(self):
        text=Path(b.__file__).read_text()
        self.assertIn("repo/'ci/firebase-test-config.plist'",text)
        self.assertNotIn('prepare-app.sh',text)
        self.assertNotIn('log stream',text)
        self.assertNotIn('sample ',text)
        self.assertNotIn('secrets.',json.dumps(self.workflow))
        self.assertIn("'--retry','0'",text)
        self.assertEqual(text.count("c.run('resolve-once'"),1)
        self.assertEqual(text.count("c.run('xcodebuild-test'"),1)

class ProcessContracts(unittest.TestCase):
    def commands(self,path,budget=None):
        return b.Commands(path,path,dict(os.environ),budget or b.Budget(time.monotonic()))
    def test_success_process_group_and_no_duplicate(self):
        with tempfile.TemporaryDirectory() as d:
            c=self.commands(Path(d))
            data=c.run('synthetic',[sys.executable,'-c','print("ok")'],2)
            self.assertEqual(data,b'ok\n');self.assertTrue(c.settled)
            self.assertEqual(c.phases[0]['raw_exit'],0)
            with self.assertRaises(b.Invalid):c.run('synthetic',[sys.executable,'-c','print("again")'])
    def test_failed_command_preserves_raw_exit(self):
        with tempfile.TemporaryDirectory() as d:
            c=self.commands(Path(d))
            with self.assertRaises(b.Invalid):c.run('synthetic',[sys.executable,'-c','raise SystemExit(37)'],2)
            self.assertEqual(c.phases[0]['raw_exit'],37);self.assertTrue(c.settled)
    def test_timeout_preserves_primary_when_settlement_fails(self):
        class Child:
            pid=123456
            def wait(self,timeout):raise subprocess.TimeoutExpired('synthetic',timeout)
            def poll(self):return None
        with tempfile.TemporaryDirectory() as d:
            c=self.commands(Path(d))
            with patch.object(subprocess,'Popen',return_value=Child()),patch.object(c,'settle',side_effect=PermissionError('synthetic denial')):
                with self.assertRaises(subprocess.TimeoutExpired):c.run('synthetic',['uninvoked'],.05)
            self.assertFalse(c.settled);self.assertTrue(c.phases[0]['timed_out'])
            self.assertIsNone(c.phases[0]['raw_exit'])
            self.assertIn('PermissionError',c.phases[0]['settlement_error'])
    def test_stubbed_termination_targets_only_owned_group(self):
        class Child:
            pid=123456
            returncode=None
            def poll(self):return self.returncode
            def wait(self,timeout):self.returncode=-signal.SIGTERM;return self.returncode
        with tempfile.TemporaryDirectory() as d:
            c=self.commands(Path(d));c.child=Child();c.settled=False
            with patch.object(c,'alive',side_effect=[True,False,False,False]),patch.object(os,'killpg') as kill:
                c.settle(time.monotonic()+75)
            self.assertTrue(c.settled)
            kill.assert_called_once_with(123456,signal.SIGTERM)
    def test_unknown_ownership_cannot_be_signalled(self):
        with tempfile.TemporaryDirectory() as d:
            c=self.commands(Path(d))
            with patch.object(os,'killpg') as kill:c.settle(time.monotonic()+75)
            kill.assert_not_called()
    def test_unsettled_child_blocks_next_phase(self):
        with tempfile.TemporaryDirectory() as d:
            c=self.commands(Path(d));c.child=object();c.settled=False
            with patch.object(subprocess,'Popen') as popen,self.assertRaises(b.Invalid):c.run('never',['uninvoked'])
            popen.assert_not_called();self.assertEqual(c.phases,[])
    def test_exhausted_phase_starts_no_child(self):
        with tempfile.TemporaryDirectory() as d:
            budget=b.Budget(0,clock=lambda:2690)
            c=self.commands(Path(d),budget)
            with patch.object(subprocess,'Popen') as popen,self.assertRaises(b.Invalid):c.run('never',['uninvoked'])
            popen.assert_not_called();self.assertEqual(c.phases,[])
    def test_finalization_uses_original_deadline(self):
        with tempfile.TemporaryDirectory() as d:
            budget=b.Budget(0,clock=lambda:3280)
            c=self.commands(Path(d),budget)
            with patch.object(subprocess,'Popen') as popen,self.assertRaises(b.Invalid):c.run('never',['uninvoked'],final=True)
            popen.assert_not_called()

class MarkerContracts(unittest.TestCase):
    def fixture(self):
        run='11111111-2222-4333-8444-555555555555'
        base={'schema':1,'run':run,'pid':99,'seq':1,'tick':1.,'stage':'ready','id':0,'command':'none','requested':-1,'enabled':False,'authorization':'notDetermined','queued':0,'hasCoverage':False,'hasMessage':False,'storageBlocked':False,'cleanupPending':False,'busy':False,'loaded':False,'operations':0}
        records=[base]
        for n,stage in enumerate(['bindingSetter','sendEntry','statusPublished','sendComplete'],2):
            r=dict(base,seq=n,tick=float(n),stage=stage,id=0 if n==2 else 1,command='enable',requested=1,enabled=n>=4,queued=8 if n>=4 else 0,loaded=n>=4)
            records.append(r)
        summary={'totalTestCount':1,'skippedTests':0,'expectedFailures':0,'passedTests':1,'failedTests':0,'result':'Passed'}
        tests={'devices':[{'modelName':'iPhone 17 Pro','architecture':'arm64','osVersion':'27.0','osBuildNumber':'24A434','platform':'iOS Simulator','deviceId':'owned'}], 'testNodes':[{'nodeType':'Test Case','nodeIdentifier':b.CASE,'result':'Passed'}]}
        activities={'activitySummaries':[{'title':'Checking value == "0" reminder-enabled','start':'2026-01-01T00:00:02+00:00','finish':'2026-01-01T00:00:03+00:00'},{'title':'Tap Switch (First Match)','start':'2026-01-01T00:00:04+00:00','finish':'2026-01-01T00:00:05+00:00'}]}
        session="Test Case '-[DailyWhiskersUITests.ReminderUITests testDiagnosticInitialEnableProbe]' started.\n"+'Launched app with identifier: com.example.kenwidemon.dailywhiskers (pid = 99)\n"DW_REMINDER_TEST_ID" = "'+run+'";\n'
        session += '00:00:02.000 runner <XCTWaiter: off> entering wait loop for 15.00s with expectations: `Expect predicate `value == "0"` for object "reminder-enabled" Switch`\n'
        session += '00:00:03.000 runner Returning result XCTWaiterResultCompleted for synchronous waiter <XCTWaiter: off>\n'
        session += '00:00:04.100 runner <XCTWaiter: tap> entering wait loop for 30.05s with expectations: `synthesizing event`\n'
        session += '00:00:04.200 runner Received kAXUserTestingNotification from AX element pid: 99, elementOrHash.elementID: 0.1: {\n    event = TouchEventsCompleted;\n}\n'
        session += '00:00:04.300 runner Returning result XCTWaiterResultCompleted for synchronous waiter <XCTWaiter: tap>\n'
        session += '00:00:04.400 runner Event synthesis future completed in 0.28s\n'
        session += "Test Case '-[DailyWhiskersUITests.ReminderUITests testDiagnosticInitialEnableProbe]' passed (5.000 seconds).\n"
        return records,session,summary,tests,activities
    def raw(self,records):
        return '\n'.join('2026-01-01 00:00:01.000000+0000 DailyWhiskers[99:1] [ReminderEnableProbe] DWReminderEnableProbe '+' '.join(k+'='+str(v).lower() if isinstance(v,bool) else k+'='+str(v) for k,v in r.items()) for r in records)
    def validate(self,records=None,**kwargs):
        r,s,summary,t,a=self.fixture()
        return b.validate_capture(self.raw(r if records is None else records),kwargs.get('session',s),kwargs.get('summary',summary),kwargs.get('tests',t),kwargs.get('activities',a),kwargs.get('uid','owned'),kwargs.get('source',True))
    def test_complete_chain_variable_count_and_queue(self):
        v=self.validate();self.assertTrue(v['capture_valid'],v['capture_errors']);self.assertEqual(len(v['records']),5)
        self.assertIn('observability/nonreproduction',v['outcome'])
        self.assertEqual(v['records'][-1]['queued'],8)
    def test_missing_completion_positive_prefix_valid(self):
        r,*_=self.fixture();v=self.validate(r[:-1]);self.assertTrue(v['capture_valid'],v['capture_errors']);self.assertIn('unfinished',v['outcome'])
    def test_missing_entry_gap_not_task_cause(self):
        r,*_=self.fixture();v=self.validate(r[:2]);self.assertTrue(v['capture_valid']);self.assertIn('Task cause not established',v['outcome'])
    def test_missing_setter_qualified_not_proof(self):
        r,*_=self.fixture();v=self.validate(r[:1]);self.assertTrue(v['capture_valid']);self.assertIn('not infrastructure proof',v['outcome'])
    def test_off_is_model_result(self):
        r,*_=self.fixture();r[-1]['enabled']=False;v=self.validate(r);self.assertTrue(v['capture_valid']);self.assertIn('Off',v['outcome'])
    def test_missing_ready_gap_pid_schema_order_malformed(self):
        for mutate in [lambda r:r[1:],lambda r:r[:1]+r[2:],lambda r:[dict(x,pid=88) for x in r],lambda r:[dict(x,schema=2) for x in r],lambda r:[r[0],r[1],r[3],r[2],r[4]],lambda r:[dict(x,tick=float('nan')) for x in r]]:
            r,*_=self.fixture();v=self.validate(mutate(r));self.assertFalse(v['capture_valid']);self.assertFalse(v['negative_marker_inference_qualified'])
    def test_source_device_case_session_and_preattempt_guards(self):
        r,s,summary,t,a=self.fixture()
        wrong=copy.deepcopy(t);wrong['testNodes'][0]['nodeIdentifier']='Other/test()'
        late=copy.deepcopy(a);late['activitySummaries'][0]['finish']='2026-01-01T00:00:06+00:00'
        for kwargs in [{'source':False},{'uid':'other'},{'session':''},{'tests':wrong},{'activities':late},{'summary':dict(summary,totalTestCount=2)},{'activities':{}}]:
            v=self.validate(**kwargs);self.assertFalse(v['negative_marker_inference_qualified'],kwargs)
    def test_passive_readiness_delivery_fail_closed(self):
        r,s,_,_,a=self.fixture()
        for changed in [s.replace('pid: 99,','pid: 98,'),s.replace('TouchEventsCompleted','OtherEvent'),s.replace('XCTWaiter: off>\n','XCTWaiter: other>\n'),s.replace('XCTWaiter: tap>\n','XCTWaiter: other>\n'),s.replace('Event synthesis future completed','Event synthesis future failed')]:
            v=self.validate(session=changed)
            self.assertTrue(v['capture_valid'],v['capture_errors'])
            self.assertFalse(v['negative_marker_inference_qualified'])
        failed=copy.deepcopy(a);failed['activitySummaries'][1]['failureSummaryIDs']=['failure']
        self.assertFalse(self.validate(activities=failed)['negative_marker_inference_qualified'])
    def test_missing_or_inconsistent_terminal_disables_only_negative_inference(self):
        r,s,_,_,_=self.fixture()
        terminal="Test Case '-[DailyWhiskersUITests.ReminderUITests testDiagnosticInitialEnableProbe]' passed (5.000 seconds).\n"
        for changed in [s.replace(terminal,''),s.replace('passed (5.000','failed (5.000'),s+terminal.replace('5.000','7.000')]:
            v=self.validate(session=changed)
            self.assertTrue(v['capture_valid'],v['capture_errors'])
            self.assertFalse(v['negative_marker_inference_qualified'])
        v=self.validate(session=s+terminal)
        self.assertTrue(v['negative_marker_inference_qualified'],v['negative_inference_errors'])
    def test_refresh_interleaving_retained(self):
        r,*_=self.fixture()
        refresh=[dict(r[0],seq=3,tick=2.5,stage='sendEntry',id=1,command='refresh'),dict(r[0],seq=5,tick=3.5,stage='statusPublished',id=1,command='refresh'),dict(r[0],seq=7,tick=4.5,stage='sendComplete',id=1,command='refresh')]
        mixed=[r[0],r[1],refresh[0],dict(r[2],seq=4,id=2),refresh[1],dict(r[3],seq=6,id=2),refresh[2],dict(r[4],seq=8,id=2)]
        v=self.validate(mixed);self.assertTrue(v['capture_valid'],v['capture_errors']);self.assertEqual(len(v['commands']),2)
    def test_graph_mapping_no_broad_export(self):
        text='* CASTree (file or dir)\n  - Id: root\n  + exact.txt (plainFile)\n    * raw\n      - Id: leaf\n'
        n=b.parse_graph(text);self.assertEqual(n['children'][0]['ref'],'leaf')
        class C:
            def run(self,*args,**kwargs):return b'[{"name":"wrong.txt","type":1}]'
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(b.Invalid):b.Collector(C(),Path('/retained'),Path(d)).directory(n)
    def test_artifact_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);(p/'unsafe').symlink_to('/etc/hosts')
            with self.assertRaises(b.Invalid):b.manifest(p,b.Budget(time.monotonic()))

class ExecutionFailureContracts(unittest.TestCase):
    """All external phases are stubs, not app/simulator/network commands."""
    def scenario(self, fail=None, uncertain=False, raw_exit=0, collector_error=False):
        import io
        import zipfile
        archive_buffer=io.BytesIO()
        with zipfile.ZipFile(archive_buffer,'w') as z:
            z.writestr(zipfile.ZipInfo('xcodegen/bin/xcodegen',(2026,1,1,0,0,0)),b'synthetic')
        archive_bytes=archive_buffer.getvalue()
        with tempfile.TemporaryDirectory() as d:
            top=Path(d);repo=top/'repository';repo.mkdir()
            (repo/b.LOCK).parent.mkdir(parents=True);(repo/b.LOCK).write_text('{"pins":[]}')
            (repo/'ci').mkdir();(repo/'ci/firebase-test-config.plist').write_text('fake-only')
            (repo/'DailyWhiskers/Resources').mkdir(parents=True)
            root=top/'reminder-boundary';root.mkdir()
            (root/'budget.json').write_text(json.dumps({'sha':'a'*40,'run_id':'123','attempt':'1','started_monotonic':time.monotonic()}))
            env=Contract().env();env.update(GITHUB_WORKSPACE=str(repo),RUNNER_TEMP=str(top))
            devices={};called=[];instances=[]
            uid='11111111-2222-4333-8444-555555555555'
            class FakeCommands:
                def __init__(self,evidence,cwd,env,budget):
                    self.evidence,self.cwd,self.budget=evidence,cwd,budget
                    self.phases=[];self.settled=True;self.child=None;instances.append(self)
                def settle(self,deadline):
                    if uncertain: self.settled=False;raise b.Invalid('synthetic unresolved group')
                    self.settled=True
                def run(self,name,argv,cap=60,final=False,check=True):
                    b.require(self.settled,'Prior synthetic group unresolved')
                    self.budget.allowance(cap,final)
                    called.append(name)
                    phase={'name':name,'argv':argv,'raw_exit':0,'owned_pgid':90000+len(called)}
                    self.phases.append(phase)
                    if name=='create-simulator':
                        devices[uid]={'udid':uid,'name':argv[3],'deviceTypeIdentifier':b.TYPE,'runtime':b.RUNTIME,'isAvailable':True,'state':'Shutdown'}
                    if name==fail:
                        phase['raw_exit']=None
                        if uncertain:self.settled=False
                        raise b.Invalid('synthetic failure '+name)
                    if name=='source-head':return b'a'*40+b'\n'
                    if name=='source-status':return b''
                    if name=='source-tree':return b'tree\n'
                    if name=='source-files':return (b.LOCK+'\0ci/firebase-test-config.plist\0').encode()
                    if name=='probe-patch':return b'probe'
                    if name=='toolchain-xcode':return b'Xcode 27.2\nBuild version 27B52\n'
                    if name=='toolchain-sdk':return b'27.2\n'
                    if name=='toolchain-arch':return b'arm64\n'
                    if name=='toolchain-runtimes':return json.dumps({'runtimes':[{'identifier':b.RUNTIME,'isAvailable':True,'version':'27.0','buildversion':'24A434'}]}).encode()
                    if name=='download-xcodegen':(root/'build/xcodegen.zip').write_bytes(archive_bytes)
                    if name=='xcodegen-version':return b'Version: 2.46.0\n'
                    if name=='resolve-once':(root/'build/SourcePackages/workspace-state.json').write_text('{"object":{"dependencies":[]}}')
                    if name=='create-simulator':return uid.encode()
                    if name=='boot-simulator':devices[uid]['state']='Booted'
                    if name=='xcodebuild-test':
                        (self.evidence/'ReminderBoundary.xcresult').mkdir()
                        phase['raw_exit']=raw_exit
                    if name=='cleanup-shutdown':devices[uid]['state']='Shutdown'
                    if name=='cleanup-delete':devices.pop(uid)
                    if name in ('devices-before','devices-created','devices-ready','cleanup-snapshot','cleanup-readback'):
                        return json.dumps({'devices':{b.RUNTIME:[dict(d) for d in devices.values()]}}).encode()
                    return b''
            class FakeCollector:
                def __init__(self,*args):called.append('collector-created')
                def collect(self,*args):
                    if collector_error:raise b.Invalid('synthetic collector failed')
                    return {'capture_valid':True,'actual_cases':[{'nodeIdentifier':b.CASE}],'legacy_execution_count':1}
            with patch.object(b,'Commands',FakeCommands),patch.object(b,'Collector',FakeCollector),patch.object(b,'PATCH_SHA',b.sha(b'probe')),patch.object(b,'XCODEGEN_SHA',b.sha(archive_bytes)):
                result=b.execute(env)
            status=json.loads((root/'evidence/status.json').read_text())
            cleanup=json.loads((root/'evidence/cleanup.json').read_text())
            return result,status,cleanup,called,dict(devices),(root/'upload-eligible').exists()
    def test_stubbed_complete_route(self):
        result,status,cleanup,calls,devices,upload=self.scenario()
        self.assertEqual(result,0);self.assertTrue(cleanup['verified']);self.assertEqual(devices,{})
        self.assertEqual(calls.count('resolve-once'),1);self.assertEqual(calls.count('xcodebuild-test'),1)
        self.assertTrue(status['test_process_spawned']);self.assertEqual(status['actual_execution_count'],1)
        self.assertTrue(upload)
    def test_fail_each_setup_phase_stops_before_test(self):
        for phase in ('source-head','source-status','probe-patch','source-tree','source-files','toolchain-xcode','toolchain-sdk','toolchain-arch','toolchain-runtimes','devices-before','download-xcodegen','unzip-xcodegen','xcodegen-version','generate-project','resolve-once','create-simulator','devices-created','boot-simulator','wait-bootstatus','devices-ready'):
            with self.subTest(phase=phase):
                result,status,cleanup,calls,devices,upload=self.scenario(fail=phase)
                self.assertEqual(result,1);self.assertIn(phase,status['primary_error'])
                self.assertNotIn('xcodebuild-test',calls);self.assertFalse(status['test_process_spawned']);self.assertEqual(status['test_invocations'],0)
                self.assertEqual(devices,{})
    def test_native_failure_raw_exit_not_swallowed(self):
        result,status,cleanup,calls,devices,upload=self.scenario(raw_exit=65)
        self.assertEqual(result,1);self.assertEqual(status['raw_test_exit'],65)
        self.assertTrue(cleanup['verified']);self.assertEqual(calls.count('xcodebuild-test'),1)
    def test_unresolved_test_group_blocks_cleanup_extraction_hash(self):
        result,status,cleanup,calls,devices,upload=self.scenario(fail='xcodebuild-test',uncertain=True)
        self.assertEqual(result,1);self.assertFalse(cleanup['verified']);self.assertFalse(upload)
        self.assertNotIn('cleanup-delete',calls);self.assertNotIn('collector-created',calls)
        self.assertIsNone(status['raw_test_exit']);self.assertEqual(len(devices),1)
    def test_collector_failure_cannot_pass(self):
        result,status,cleanup,calls,devices,upload=self.scenario(collector_error=True)
        self.assertEqual(result,1);self.assertFalse(status['collector_valid']);self.assertTrue(cleanup['verified'])
    def test_cleanup_failure_cannot_pass_or_delete_twice(self):
        for phase in ('cleanup-snapshot','cleanup-shutdown','cleanup-delete','cleanup-readback'):
            with self.subTest(phase=phase):
                result,status,cleanup,calls,devices,upload=self.scenario(fail=phase)
                self.assertEqual(result,1);self.assertFalse(cleanup['verified'])
                self.assertLessEqual(calls.count('cleanup-delete'),1)

class AdditionalEvidenceContracts(unittest.TestCase):
    def test_additional_iteration_rejected_before_leaf_read(self):
        with tempfile.TemporaryDirectory() as d:
            collector=b.Collector(None,Path('/retained'),Path(d))
            entries=[{'name':'DailyWhiskersUITests-AAAA-Configuration-Test Scheme Action-Iteration-'+str(n),'type':2} for n in (1,2)]
            graph='* CASTree (file or dir)\n  - Id: root\n'+''.join('  + '+e['name']+' (directory)\n' for e in entries)+''.join('    * CASTree (file or dir)\n      - Id: child'+str(n)+'\n' for n in (1,2))
            def get(argv):return graph.encode() if argv[0]=='graph' else b'{}'
            def obj(ref=None,raw=False):return json.dumps(entries).encode() if raw else {'actions':[{'actionResult':{'diagnosticsRef':{'id':'root'}}}]}
            with patch.object(collector,'get',side_effect=get),patch.object(collector,'obj',side_effect=obj):
                with self.assertRaisesRegex(b.Invalid,'Additional/ambiguous'):collector.collect()
    def test_duplicate_session_case_start_is_invalid(self):
        helper=MarkerContracts();r,s,_,_,_=helper.fixture()
        s+="\nTest Case '-[DailyWhiskersUITests.ReminderUITests testDiagnosticInitialEnableProbe]' started.\n"
        self.assertFalse(helper.validate(session=s)['capture_valid'])
    def test_artifact_cap_and_original_deadline(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);(p/'fourbytes').write_bytes(b'abcd')
            with patch.object(b,'MAX_ARTIFACT',3),self.assertRaisesRegex(b.Invalid,'cap'):b.manifest(p,b.Budget(time.monotonic()))
            with self.assertRaisesRegex(b.Invalid,'deadline'):b.manifest(p,b.Budget(0,clock=lambda:3290))
    @unittest.skipUnless(os.environ.get('DW_BOUNDARY_RETAINED_LOCAL'),'Retained evidence path not supplied')
    def test_retained_session_truncation_keeps_positive_evidence_only(self):
        p=Path(os.environ['DW_BOUNDARY_RETAINED_LOCAL'])
        raw=(p/'app-stdout-stderr.txt').read_text();session=(p/'Session.log').read_text()
        tests=json.loads((p/'tests.json').read_text());summary=json.loads((p/'summary.json').read_text());activities=json.loads((p/'test-activities.json').read_text())
        stripped=re.sub(r"(?m)^Test Case '-\[DailyWhiskersUITests\.ReminderUITests testDiagnosticInitialEnableProbe\]' (passed|failed) \([^\n]+\n",'',session)
        for changed in (stripped,session[:session.index("Test Case '-[DailyWhiskersUITests.ReminderUITests testDiagnosticInitialEnableProbe]' passed")]):
            v=b.validate_capture(raw,changed,summary,tests,activities,tests['devices'][0]['deviceId'],True)
            self.assertTrue(v['capture_valid'],v['capture_errors'])
            self.assertFalse(v['negative_marker_inference_qualified'])
            self.assertEqual(len(v['records']),11)
            self.assertTrue(any('terminal' in e for e in v['negative_inference_errors']))
    @unittest.skipUnless(os.environ.get('DW_BOUNDARY_RETAINED_LOCAL'),'Retained evidence path not supplied')
    def test_retained_local_evidence_under_actual_interpreter(self):
        p=Path(os.environ['DW_BOUNDARY_RETAINED_LOCAL'])
        raw=(p/'app-stdout-stderr.txt').read_bytes()
        self.assertEqual(b.sha(raw),'7460a064d54779409e165c6667454c85fd51a799e750ccc0ed55c5241e5ada52')
        tests=json.loads((p/'tests.json').read_text())
        v=b.validate_capture(raw.decode(),(p/'Session.log').read_text(),json.loads((p/'summary.json').read_text()),tests,json.loads((p/'test-activities.json').read_text()),tests['devices'][0]['deviceId'],True)
        self.assertTrue(v['capture_valid'],v['capture_errors'])
        self.assertTrue(v['negative_marker_inference_qualified'],v['negative_inference_errors'])
        self.assertEqual(len(v['records']),11)  # Fixture regression only; not collector's count contract.

if __name__=='__main__':
    unittest.main()

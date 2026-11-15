"""Offline denial projection fixtures executing the actual parsed workflow Python.

No app, simulator, network or hosted action is executed. f128 is a retained source
comparison, not approval to publish or rerun that consumed hosted attempt.
"""
import ast
import builtins
import contextlib
import copy
import errno
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
BASE = 'f12883ddb3aae1205f0a68ae5ecf0dd3b110a5d2'
DENIAL = 'Evidence upload unavailable or insufficient original job budget'
BUDGET = dict(started_monotonic=100,sha='a'*40,run_id='123',attempt='1',contract_sha256='b'*64)
IDENTITY = dict(GITHUB_SHA='a'*40,APPROVED_SHA='a'*40,GITHUB_RUN_ID='123',GITHUB_RUN_ATTEMPT='1',APPROVED_CONTRACT_SHA256='b'*64)
LEAK = 'SYNTHETIC_SECRET_123 /Users/private/account token=SECRET ::warning::injected\n\x1b[31m\rcommand --credential=SECRET'
PATHS = {'phases':'evidence/phases.json','status':'evidence/status.json','cleanup':'evidence/cleanup.json',
         'prefix':'evidence/snapshot-export-receipt.json','collector':'evidence/collector-verdict.json','artifact':'artifact-blocker.json'}

def yaml_document(raw):
    return json.loads(subprocess.check_output(['ruby','-rpsych','-rjson','-e',
        'puts JSON.generate(Psych.safe_load(STDIN.read, permitted_classes: [Date], aliases: false))','-rdate'], input=raw))

def gate_script(document):
    gate = document['jobs']['reminder-boundary']['steps'][-2]
    return gate['run'].split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]

def phase(name='xcodebuild-test', **extra):
    return dict(name=name, argv=[LEAK], owned_pgid=123, raw_exit=65, group_settled=True,
                started_tick=110.0, execution_deadline=2800, finalization_deadline=3400,
                finished_tick=120.0, finished_at='2026-11-15T00:00:00+00:00', **extra)

def status(**extra):
    result = dict(finished_at='2026-11-15T00:00:00+00:00',test_process_spawned=True,test_invocations=1,
                  raw_test_exit=65,primary_error=None,cleanup_errors=[],cleanup_verified=True,
                  collector_valid=False,snapshot_valid=False,identity=dict(IDENTITY, secret=LEAK))
    result.update(extra)
    return result

class DenialProjection(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.old_yaml = yaml_document(subprocess.check_output(['git','-C',str(REPO),'show',BASE+':.github/workflows/ios.yml']))
        cls.new_yaml = yaml_document((REPO/'.github/workflows/ios.yml').read_bytes())
        cls.old_code = gate_script(cls.old_yaml); cls.new_code = gate_script(cls.new_yaml)
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.top = Path(self.temp.name).resolve(); self.root = self.top/'reminder-boundary'
        self.root.mkdir(); (self.root/'evidence').mkdir(); self.output = self.top/'output'
        (self.root/'budget.json').write_text(json.dumps(BUDGET))
    def write(self, label, doc):
        (self.root/PATHS[label]).write_text(json.dumps(doc))
    def run_gate(self, code=None, marker=False, remaining=400, faults=()):
        marker_path = self.root/'upload-eligible'
        if marker: marker_path.write_text('manifest complete\n')
        elif marker_path.exists(): marker_path.unlink()
        if self.output.exists() and self.output.is_file():self.output.unlink()
        writes=[]; marker_reads=[]; receipt_reads=[]; real_is_file=Path.is_file; real_read=os.read
        def is_file(path):
            if path == marker_path:marker_reads.append(str(path))
            return real_is_file(path)
        def read(fd,count):
            receipt_reads.append(count)
            return real_read(fd,count)
        def write(fd,raw):
            self.assertEqual(fd,1);writes.append(raw);return len(raw)
        error=None
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch.dict(os.environ, {'RUNNER_TEMP':str(self.top),'GITHUB_OUTPUT':str(self.output)},clear=True))
            stack.enter_context(patch.object(time,'monotonic',return_value=3700-remaining))
            stack.enter_context(patch.object(Path,'is_file',is_file))
            stack.enter_context(patch.object(os,'write',write))
            stack.enter_context(patch.object(os,'read',read))
            stack.enter_context(patch.object(subprocess,'Popen',side_effect=AssertionError('External process forbidden')))
            for fault in faults:stack.enter_context(fault)
            try:exec(compile(code or self.new_code, 'actual-yaml-upload-gate','exec'),{})
            except BaseException as exc:error=(type(exc).__name__,str(exc))
        return {'error':error,'output':self.output.read_text() if self.output.is_file() else None,
                'writes':writes,'marker_reads':len(marker_reads),'receipt_reads':receipt_reads}
    def summary(self, **kwargs):
        result=self.run_gate(**kwargs)
        self.assertEqual(result['error'],('SystemExit',DENIAL));self.assertEqual(result['output'],'upload=false\n')
        self.assertEqual(result['marker_reads'],1);self.assertEqual(len(result['writes']),1)
        raw=result['writes'][0];self.assertLessEqual(len(raw),4096)
        self.assertTrue(raw.startswith(b'Reminder receipt summary: '));self.assertTrue(raw.endswith(b'\n'))
        self.assertTrue(all(32<=ch<=126 for ch in raw[:-1]))
        self.assertNotIn(b'::',raw);self.assertNotIn(b'SYNTHETIC_SECRET',raw);self.assertNotIn(b'/Users/',raw)
        return json.loads(raw.split(b': ',1)[1])
    def test_extracted_gate_decision_outputs_exits_and_read_count(self):
        for marker in (False,True):
            for left in (299.999,300,300.001,-1,400):
                with self.subTest(marker=marker,left=left):
                    old=self.run_gate(self.old_code,marker,left);new=self.run_gate(self.new_code,marker,left)
                    for key in ('error','output','marker_reads'):self.assertEqual(old[key],new[key])
                    self.assertEqual(old['marker_reads'],1)
                    if marker and left>=300:
                        self.assertEqual(new['writes'],[]);self.assertEqual(new['receipt_reads'],[])
    def test_exact_gate_ast_change_only_capture_and_denial_body(self):
        old=ast.parse(self.old_code);new=ast.parse(self.new_code)
        original=copy.deepcopy(new)
        assigned=next(n for n in original.body if isinstance(n,ast.Assign) and n.targets[0].id=='allowed')
        self.assertIsInstance(assigned.value.values[0],ast.NamedExpr)
        self.assertEqual(assigned.value.values[0].target.id,'marker_present')
        assigned.value.values[0]=assigned.value.values[0].value
        original.body[-1].body=original.body[-1].body[-1:]
        self.assertEqual(ast.dump(old),ast.dump(original))
        old_doc=copy.deepcopy(self.old_yaml);new_doc=copy.deepcopy(self.new_yaml)
        # Admit only the separately reviewed fresh-branch literal in the initial
        # dispatch guard. Retain whole-guard and whole-document equivalence.
        old_steps=old_doc['jobs']['reminder-boundary']['steps']
        new_steps=new_doc['jobs']['reminder-boundary']['steps']
        old_ref="'GITHUB_REF': 'refs/heads/codex/pr143-hosted-prefix-witness-20261115'"
        new_ref="'GITHUB_REF': 'refs/heads/codex/pr143-denial-reporting-hosted-20261115'"
        self.assertEqual(old_steps[0]['run'].count(old_ref),1)
        self.assertEqual(new_steps[0]['run'].count(new_ref),1)
        expected_guard=old_steps[0]['run'].replace(old_ref,new_ref)
        self.assertEqual(new_steps[0]['run'],expected_guard)
        old_steps[0]['run']=expected_guard
        old_doc['jobs']['reminder-boundary']['steps'][-2]['run']='same'
        new_doc['jobs']['reminder-boundary']['steps'][-2]['run']='same'
        self.assertEqual(old_doc,new_doc)
    def test_approved_path_does_not_import_or_invoke_reporter(self):
        real_import=builtins.__import__
        def restricted(name,*a,**k):
            self.assertNotIn(name,('datetime','errno','math','re','stat'))
            return real_import(name,*a,**k)
        result=self.run_gate(marker=True,remaining=300,faults=(patch('builtins.__import__',restricted),patch.object(os,'open',side_effect=AssertionError('reporter open')),))
        self.assertIsNone(result['error']);self.assertEqual(result['output'],'upload=true\n')
    def test_gate_reason_combinations(self):
        for marker,left,reasons in [(False,400,['MARKER_MISSING']),(True,299,['RESERVE_INSUFFICIENT']),(False,299,['MARKER_MISSING','RESERVE_INSUFFICIENT'])]:
            doc=self.summary(marker=marker,remaining=left)
            self.assertEqual(doc['gate_reasons'],reasons);self.assertEqual(doc['marker_present_at_gate'],marker)
            self.assertEqual(doc['remaining_seconds_at_gate'],left)
            self.assertEqual(doc['reserve_comparison_evaluated_by_gate'],marker)
            self.assertEqual(doc['reserve_predicate_on_gate_remaining'],left>=300)
    def test_missing_receipts_and_setup_unknowns(self):
        doc=self.summary()
        self.assertEqual({x['state'] for x in doc['receipts'].values()},{'absent'})
        self.assertEqual(doc['failing_phase'],'unknown');self.assertEqual(doc['app_test_outcome'],'unknown')
    def test_stale_pretest_status_does_not_claim_no_test_or_error(self):
        self.write('status',{'test_process_spawned':False,'test_command_planned':True,'raw_test_exit':None,'primary_error':None,'cleanup_errors':[]})
        self.write('phases',[phase()])
        doc=self.summary()['receipts'];self.assertEqual(doc['status'],{'state':'incomplete','final_fields':'unknown'})
        self.assertEqual(doc['phases']['test_process']['process_spawn'],'recorded-true')
    def test_interrupted_finalization_incomplete_phase_unknown_exit(self):
        self.write('phases',[{'name':'source-head','argv':[LEAK]},{'name':'xcodebuild-test','owned_pgid':2}])
        self.write('cleanup',{'verified':False,'error':LEAK})
        doc=self.summary()['receipts'];self.assertEqual(doc['phases']['state'],'incomplete')
        self.assertIsNone(doc['phases']['test_process']['raw_exit']);self.assertEqual(doc['cleanup']['state'],'incomplete')
    def test_timeout_unsettled_and_primary_cleanup_artifact_separate(self):
        self.write('phases',[dict(phase(),timed_out=True,raw_exit=None,group_settled=False,primary_error='TimeoutExpired: '+LEAK,settlement_error='Invalid: '+LEAK)])
        self.write('status',status(raw_test_exit=None,primary_error='TimeoutExpired: '+LEAK,cleanup_verified=False,cleanup_errors=['Owned group not settled; simulator cleanup forbidden']))
        self.write('artifact',{'error':'Unresolved owned group; bundle may be mutating, no extraction/hash/upload eligibility'})
        doc=self.summary()['receipts'];self.assertEqual(doc['phases']['test_process']['timed_out'],'recorded-true')
        self.assertEqual(doc['status']['primary_error'],'TIMEOUT_RECORDED');self.assertEqual(doc['status']['cleanup_errors'],['OWNED_GROUP_UNSETTLED'])
        self.assertEqual(doc['artifact']['error'],'OWNED_GROUP_UNSETTLED')
    def test_last_phase_is_not_failure_phase(self):
        self.write('phases',[phase(),dict(phase('cleanup-readback'),raw_exit=0)])
        doc=self.summary();self.assertEqual(doc['failing_phase'],'unknown')
        self.assertEqual(doc['receipts']['phases']['last_recorded_phase']['name'],'cleanup-readback')
        self.assertEqual(doc['receipts']['phases']['test_process']['raw_exit'],65)
    def test_absent_exit_never_invented_from_settlement(self):
        self.write('phases',[dict(name='xcodebuild-test',owned_pgid=4,group_settled=True,finished_tick=5)])
        doc=self.summary()['receipts']['phases'];self.assertEqual(doc['state'],'incomplete')
        self.assertIsNone(doc['test_process']['raw_exit'])
    def test_conflicting_receipts_are_explicit_recordings(self):
        self.write('status',status(raw_test_exit=0));self.write('phases',[phase()])
        self.write('cleanup',{'verified':False,'owned_deleted':False,'preexisting_stable':False})
        self.write('prefix',{'exported':True,'classification':{'valid':True,'kind':'prefix'}})
        self.write('collector',{'capture_valid':True,'actual_cases':[]})
        doc=self.summary();self.assertEqual(doc['conflicting_recordings'],['cleanup','prefix','collector','test-process'])
        self.assertEqual(doc['app_test_outcome'],'unknown')
    def test_internal_conflicts_not_successful_claims(self):
        self.write('status',status(test_process_spawned=False,test_invocations=0))
        self.write('cleanup',{'verified':True,'owned_deleted':False,'preexisting_stable':True})
        self.write('prefix',{'exported':False,'classification':{'valid':True}})
        doc=self.summary()['receipts']
        for label in ('status','cleanup','prefix'):self.assertEqual(doc[label]['state'],'conflicting')
    def test_artifact_error_mapping_exact_source_messages(self):
        expected={'Unresolved owned group; bundle may be mutating, no extraction/hash/upload eligibility':'OWNED_GROUP_UNSETTLED',
                  'Finalization hashing deadline':'FINALIZATION_HASH_DEADLINE','Artifact symlink':'ARTIFACT_SYMLINK',
                  'Artifact exceeds 2 GiB cap; no upload eligibility':'ARTIFACT_SIZE_CAP'}
        source=(REPO/'ci/reminder_boundary.py').read_text()
        for message,code in expected.items():
            self.assertIn(repr(message),source);self.write('artifact',{'error':message})
            self.assertEqual(self.summary()['receipts']['artifact']['error'],code)
        for message in (LEAK,'Finalization hashing deadline '+LEAK,'Invalid: Artifact symlink',''):
            self.write('artifact',{'error':message});self.assertEqual(self.summary()['receipts']['artifact']['error'],'UNCLASSIFIED_ARTIFACT_ERROR')
    def test_free_text_never_echoed_any_input(self):
        self.write('phases',[dict(phase(),primary_error=LEAK,settlement_error=LEAK)])
        self.write('status',status(primary_error=LEAK,cleanup_errors=[LEAK]))
        self.write('cleanup',{'verified':False,'error':LEAK,'metadata_differences':{'path':LEAK}})
        self.write('prefix',{'exported':False,'error':LEAK,'receipt_error':LEAK,'container':LEAK,'container_command':[LEAK]})
        self.write('collector',{'capture_valid':False,'capture_errors':[LEAK],'records':[{'identity':LEAK}]})
        self.write('artifact',{'error':LEAK})
        self.summary()
    def test_phase_names_are_source_allowlist_not_arbitrary_grammar(self):
        for name in ('secret-token','extract-0','extract-10000','package-head-01','xcodebuild-test\n::warning::x',True,LEAK):
            self.write('phases',[{'name':name}]);self.assertEqual(self.summary()['receipts']['phases']['state'],'malformed')
        for name in ('extract-1','extract-9999','package-head-0','package-head-9999'):
            self.write('phases',[{'name':name}]);self.assertEqual(self.summary()['receipts']['phases']['state'],'incomplete')
    def test_invalid_types_and_enum(self):
        invalid=[('phases',[dict(phase(),raw_exit=True)]),('phases',[dict(phase(),owned_pgid=True)]),
                 ('phases',[dict(phase(),timed_out='false')]),('phases',[phase(),phase()]),('status',status(primary_error={})),
                 ('status',status(test_invocations=True)),('status',status(test_process_spawned='false')),
                 ('status',status(finished_at='not a date')),('status',status(cleanup_errors=[1])),
                 ('cleanup',{'verified':'true'}),('prefix',{'exported':True,'classification':{'valid':True,'kind':LEAK}}),
                 ('prefix',{'classification':{'negative_marker_inference_qualified':True}}),('artifact',{'error':False}),
                 ('collector',{'capture_valid':1}),('collector',{'capture_valid':True,'actual_cases':LEAK}),
                 ('phases',[dict(phase(),finished_tick=True)]),('phases',[dict(phase(),timeout_seconds=-1)])]
        for label,doc in invalid:
            with self.subTest(label=label,doc=str(doc)[:20]):
                self.write(label,doc);self.assertEqual(self.summary()['receipts'][label]['state'],'malformed')
    def test_malformed_duplicate_nonfinite_deep_json(self):
        for raw in (b'{',b'[]',b'\xff',b'{"error":"x","error":"y"}',b'{"error":NaN}',b'{"error":1e999}',b'['*9+b'0'+b']'*9):
            (self.root/PATHS['artifact']).write_bytes(raw)
            self.assertEqual(self.summary()['receipts']['artifact']['state'],'malformed')
    def test_byte_cap_exact_and_oversized(self):
        raw=b'{"error":"unknown"}'; path=self.root/PATHS['artifact']
        path.write_bytes(raw+b' '*(65536-len(raw)))
        self.assertEqual(self.summary()['receipts']['artifact']['state'],'recorded')
        path.write_bytes(raw+b' '*(65537-len(raw)))
        self.assertEqual(self.summary()['receipts']['artifact']['state'],'oversized')
    def test_depth_field_node_and_container_bounds(self):
        self.write('artifact',{'error':'x'*4096});self.assertEqual(self.summary()['receipts']['artifact']['state'],'recorded')
        for doc in ({'error':'x'*4097},dict(error='x',unused=list(range(257))),dict(error='x',unused={str(i):0 for i in range(129)}),
                    dict(error='x',unused=[[0]*128 for _ in range(32)]),dict(error='x',unused=2**64+1)):
            self.write('artifact',doc);self.assertEqual(self.summary()['receipts']['artifact']['state'],'malformed')
        # Strings containing brackets do not count as nesting.
        self.write('artifact',{'error':'x','ignored':'['*4096});self.summary()
    def test_symlink_nonregular_hardlink_and_parent_symlink(self):
        path=self.root/PATHS['artifact'];outside=self.top/'outside';outside.write_text('{"error":"'+LEAK.split()[0]+'"}')
        path.symlink_to(outside);self.assertEqual(self.summary()['receipts']['artifact']['state'],'unsafe');path.unlink()
        os.link(outside,path);self.assertEqual(self.summary()['receipts']['artifact']['state'],'unsafe');path.unlink()
        path.mkdir();self.assertEqual(self.summary()['receipts']['artifact']['state'],'unsafe');path.rmdir()
        os.mkfifo(path);self.assertEqual(self.summary()['receipts']['artifact']['state'],'unsafe');path.unlink()
        evidence=self.root/'evidence';evidence.rmdir();evidence.symlink_to(self.top)
        self.assertEqual(self.summary()['receipts']['phases']['state'],'unsafe')
    def test_changed_file_and_short_read_unsafe(self):
        self.write('artifact',{'error':'Artifact symlink'});real_read=os.read
        def changed(fd,n):
            raw=real_read(fd,n);(self.root/PATHS['artifact']).write_bytes(b'{"error":"changed"}');return raw
        self.assertEqual(self.summary(faults=(patch.object(os,'read',changed),))['receipts']['artifact']['state'],'unsafe')
        self.assertEqual(self.summary(faults=(patch.object(os,'read',return_value=b''),))['receipts']['artifact']['state'],'unsafe')
    def test_filesystem_error_unknown_and_no_message_leak(self):
        self.write('artifact',{'error':'Artifact symlink'})
        self.assertEqual(self.summary(faults=(patch.object(os,'read',side_effect=PermissionError(LEAK)),))['receipts']['artifact']['state'],'unknown')
    def test_summary_read_parse_serialize_and_output_faults_preserve_denial(self):
        self.write('artifact',{'error':'Artifact symlink'})
        original_loads=json.loads
        def loads(raw,*a,**k):
            if 'object_pairs_hook' in k:raise RuntimeError(LEAK)
            return original_loads(raw,*a,**k)
        faults=[patch.object(os,'read',side_effect=RuntimeError(LEAK)),patch.object(json,'loads',loads),
                patch.object(json,'dumps',side_effect=RuntimeError(LEAK)),patch.object(os,'write',side_effect=BrokenPipeError(LEAK)),
                patch.object(os,'write',side_effect=KeyboardInterrupt(LEAK)),patch.object(os,'write',return_value=1)]
        for fault in faults:
            result=self.run_gate(faults=(fault,));self.assertEqual(result['error'],('SystemExit',DENIAL));self.assertEqual(result['output'],'upload=false\n')
    def test_malformed_budget_failure_behavior_unchanged(self):
        for raw in ('{','{}','{"started_monotonic":"bad"}','{"started_monotonic":null}'):
            (self.root/'budget.json').write_text(raw)
            old=self.run_gate(self.old_code);new=self.run_gate(self.new_code)
            for key in ('error','output','marker_reads','writes'):self.assertEqual(old[key],new[key])
        (self.root/'budget.json').unlink()
        self.assertEqual(self.run_gate(self.old_code)['error'],self.run_gate(self.new_code)['error'])
    def test_output_write_failure_behavior_unchanged(self):
        self.output.mkdir()
        old=self.run_gate(self.old_code);new=self.run_gate(self.new_code)
        for key in ('error','output','marker_reads','writes'):self.assertEqual(old[key],new[key])
    def test_nonfinite_budget_gate_decision_unchanged(self):
        for value in (float('nan'),float('inf'),-float('inf')):
            (self.root/'budget.json').write_text(json.dumps({'started_monotonic':value}))
            for marker in (False,True):
                old=self.run_gate(self.old_code,marker=marker);new=self.run_gate(self.new_code,marker=marker)
                for key in ('error','output','marker_reads'):self.assertEqual(old[key],new[key])
    def test_input_read_bound_and_no_unlisted_file_reads(self):
        for label in PATHS:self.write(label,[] if label=='phases' else {})
        opened=[];real_open=os.open
        def observe(path,*a,**k):
            opened.append(str(path));return real_open(path,*a,**k)
        result=self.run_gate(faults=(patch.object(os,'open',observe),))
        self.assertEqual(result['receipt_reads'],[65537]*6)
        allowed=set(self.root.parts)|{'/','evidence'}|{Path(x).name for x in PATHS.values()}
        self.assertLessEqual(set(opened),allowed)
    def test_output_cap_suppresses_oversized_serialization(self):
        result=self.run_gate(faults=(patch.object(json,'dumps',return_value='A'*4096),))
        self.assertEqual(result['error'],('SystemExit',DENIAL));self.assertEqual(result['writes'],[])
    def test_disappearance_after_read_is_unsafe_not_absent(self):
        self.write('artifact',{'error':'Artifact symlink'});real_read=os.read
        def vanished(fd,n):
            raw=real_read(fd,n);(self.root/PATHS['artifact']).unlink();return raw
        self.assertEqual(self.summary(faults=(patch.object(os,'read',vanished),))['receipts']['artifact']['state'],'unsafe')
    def test_phase_count_and_error_array_limits(self):
        self.write('phases',[phase('extract-'+str(i)) for i in range(1,129)])
        self.assertEqual(self.summary()['receipts']['phases']['state'],'recorded')
        self.write('phases',[phase('extract-'+str(i)) for i in range(1,130)])
        self.assertEqual(self.summary()['receipts']['phases']['state'],'malformed')
        self.write('status',status(cleanup_errors=['secret']*16));self.assertEqual(self.summary()['receipts']['status']['state'],'recorded')
        self.write('status',status(cleanup_errors=['secret']*17));self.assertEqual(self.summary()['receipts']['status']['state'],'malformed')
    def test_parser_depth_exact_limit(self):
        def nested(n):
            value=0
            for _ in range(n):value=[value]
            return {'error':'unknown','ignored':value}
        self.write('artifact',nested(7));self.assertEqual(self.summary()['receipts']['artifact']['state'],'recorded')
        self.write('artifact',nested(8));self.assertEqual(self.summary()['receipts']['artifact']['state'],'malformed')
    def test_summary_output_cap_exact(self):
        prefix=b'Reminder receipt summary: '
        for length,expected in ((4096-len(prefix)-1,1),(4096-len(prefix),0)):
            result=self.run_gate(faults=(patch.object(json,'dumps',return_value='A'*length),))
            self.assertEqual(result['error'],('SystemExit',DENIAL));self.assertEqual(len(result['writes']),expected)
            if expected:self.assertEqual(len(result['writes'][0]),4096)
    def test_stale_completed_status_identity_withholds_final_fields(self):
        for identity in ({},dict(IDENTITY,GITHUB_RUN_ID='999'),dict(IDENTITY,GITHUB_SHA='c'*40),dict(IDENTITY,GITHUB_RUN_ATTEMPT='2')):
            self.write('status',status(identity=identity))
            doc=self.summary()['receipts']['status']
            self.assertEqual(doc,{'state':'unknown','final_fields':'unknown','reason':'STATUS_PROVENANCE_UNVERIFIED'})
    def test_stale_phase_budget_window_withholds_recorded_claims(self):
        for update in (dict(started_tick=99),dict(execution_deadline=2700),dict(finalization_deadline=3300),dict(finished_tick=109),dict(finished_tick=9999)):
            self.write('phases',[dict(phase(),**update)])
            doc=self.summary()['receipts']['phases']['test_process']
            self.assertEqual(doc['state'],'conflicting');self.assertEqual(doc['provenance'],'unverified')
            self.assertIsNone(doc['raw_exit']);self.assertEqual(doc['process_spawn'],'unknown')
    def test_additional_internal_and_null_exit_conflicts(self):
        self.write('collector',{'capture_valid':True,'capture_errors':[LEAK],'actual_cases':[]})
        self.write('prefix',{'exported':True,'classification':{'valid':True,'errors':[LEAK]}})
        raw=phase();del raw['owned_pgid'];self.write('phases',[raw])
        doc=self.summary()['receipts']
        for label in ('collector','prefix'):self.assertEqual(doc[label]['state'],'conflicting')
        self.assertEqual(doc['phases']['test_process']['state'],'conflicting')
        self.write('phases',[dict(phase(),timed_out=False,primary_error='TimeoutExpired: '+LEAK)])
        self.assertEqual(self.summary()['receipts']['phases']['test_process']['state'],'conflicting')
        self.write('phases',[dict(phase(),raw_exit=None)]);self.write('status',status())
        self.assertIn('test-process',self.summary()['conflicting_recordings'])
    def test_nan_budget_denial_reason_matches_comparison(self):
        (self.root/'budget.json').write_text(json.dumps(dict(BUDGET,started_monotonic=float('nan'))))
        doc=self.summary(marker=True)
        self.assertFalse(doc['reserve_predicate_on_gate_remaining']);self.assertIn('RESERVE_INSUFFICIENT',doc['gate_reasons'])
        self.assertIn('BUDGET_VALUE_UNREPRESENTABLE',doc['gate_reasons']);self.assertIsNone(doc['remaining_seconds_at_gate'])
    def test_no_new_execution_or_wait_calls(self):
        tree=ast.parse(self.new_code)
        forbidden={'Popen','run','sleep','wait','system','rglob','glob','iterdir','walk','exec','eval'}
        for node in ast.walk(tree):
            if isinstance(node,ast.Call):
                name=node.func.attr if isinstance(node.func,ast.Attribute) else node.func.id if isinstance(node.func,ast.Name) else ''
                self.assertNotIn(name,forbidden)

if __name__=='__main__':unittest.main()

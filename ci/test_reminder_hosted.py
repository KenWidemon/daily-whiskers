"""Offline actual workflow/source and combined-prefix interpretation fixtures."""
import ast
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch
import reminder_boundary as b
import reminder_snapshot as s
import test_reminder_boundary as boundary_tests
from test_reminder_snapshot import fixture, encode, IDENTITY

REPO=Path(__file__).resolve().parents[1]
HELP=b"Usage: simctl get_app_container <device> <app bundle identifier> [<container>]\n data The application's data container\n"


class Help(unittest.TestCase):
    def test_stdout_stderr_and_mixed(self):
        for stdout,stderr in [(HELP,b''),(b'',HELP),tuple(HELP.split(b'\n',1))]:
            b.validate_container_help(stdout,stderr,0)
    def test_wrong_exit_semantics_encoding_or_size(self):
        for stdout,stderr,code in [(HELP,b'',1),(HELP.replace(b'[<container>]',b'<path>'),b'',0),
                (HELP.replace(b"data The application's data container",b'data Other container'),b'',0),
                (b'\xff',HELP,0),(HELP,b' '*65536,0),(b'help',b'',0)]:
            with self.subTest(code=code,stdout=stdout[:30]),self.assertRaises((b.Invalid,UnicodeError)):
                b.validate_container_help(stdout,stderr,code)


class HostedContract(unittest.TestCase):
    def test_actual_contract_and_all_tracked_hashes(self):
        raw=(REPO/b.CONTRACT).read_bytes()
        # During preparation the new files are not necessarily staged yet.
        tracked=subprocess.check_output(['git','-C',str(REPO),'ls-files','-z']).decode().split('\0')
        new=subprocess.check_output(['git','-C',str(REPO),'ls-files','--others','--exclude-standard','-z']).decode().split('\0')
        files=sorted((set(tracked)|set(new))-{''})
        contract=b.verify_contract(REPO,raw,b.sha(raw),files)
        self.assertEqual(contract['validated_source'],'bfde0cbeb3f24473e6ed3fc7dbe8f0f3ed14db79')
        self.assertEqual(contract['ref'],'refs/heads/codex/pr143-hosted-prefix-witness-20261115')
        self.assertEqual(contract['limits'],{'method_seconds':720,'execution_seconds':2700,
            'finalization_seconds':3300,'job_seconds':3600,'export_reserve_seconds':345,'upload_seconds':300})
        self.assertEqual(b.PROBE_PATHS,['DailyWhiskers/Reminders/ReminderModel.swift',
            'DailyWhiskers/Reminders/ReminderSettingsView.swift','DailyWhiskers/Reminders/ReminderSmoke.swift',
            'DailyWhiskers/Reminders/ReminderProbeSnapshot.swift','DailyWhiskersUITests/ReminderUITests.swift'])
        raw_patch=subprocess.check_output(['git','-C',str(REPO),'diff','--binary',b.BASE,'--',*b.PROBE_PATHS])
        self.assertEqual(b.sha(raw_patch),b.PATCH_SHA)
        self.assertEqual(b.PATCH_SHA,'e246fe95b7b2efe9fb2b86f82902dfa6784df57fd368e271ee8233c2b2186559')
    def test_bad_hash_inventory_identity_limits_and_changed_source(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();(root/'source').write_bytes(b'approved')
            doc={'schema':1,'validated_source':b.VALIDATED_SOURCE,'ref':b.REF,'selector':b.SELECTOR,
                'limits':b.LIMITS,'files':{'source':b.sha(b'approved')}}
            def verify(doc,approved=None,files=None):
                raw=encode(doc)
                return b.verify_contract(root,raw,approved or b.sha(raw),files or ['source',b.CONTRACT])
            verify(doc)
            with self.assertRaises(b.Invalid):verify(doc,'0'*64)
            with self.assertRaises(b.Invalid):verify(doc,files=['source',b.CONTRACT,'unreviewed'])
            for key,value in [('ref','refs/heads/codex/pr143-reminder-boundary-20261115'),('validated_source','0'*40),
                              ('selector','other-test'),('limits',dict(b.LIMITS,method_seconds=721))]:
                changed=copy.deepcopy(doc);changed[key]=value
                with self.subTest(key=key),self.assertRaises(b.Invalid):verify(changed)
            (root/'source').write_bytes(b'changed')
            with self.assertRaises(b.Invalid):verify(doc)
    def test_actual_all_workflows_manual_only(self):
        for path in sorted((REPO/'.github/workflows').glob('*.yml')):
            doc=json.loads(subprocess.check_output(['ruby','-rpsych','-rjson','-e',
                'puts JSON.generate(Psych.load_file(ARGV[0]))',str(path)]))
            self.assertEqual(set(doc.get('on',doc.get('true'))),{'workflow_dispatch'},path)
            self.assertNotIn('schedule',doc)
            if path.name=='release-rehearsal.yml':
                self.assertIn('refs/heads/codex/develop',json.dumps(doc))
    def test_parsed_guard_rejects_old_branch_bad_contract_and_input(self):
        boundary_tests.Contract.setUpClass();c=boundary_tests.Contract()
        for key,value in [('GITHUB_REF','refs/heads/codex/pr143-reminder-boundary-20261115'),
            ('APPROVED_CONTRACT_SHA256',''),('APPROVED_CONTRACT_SHA256','A'*64),('APPROVED_CONTRACT_SHA256','a'*63),
            ('CACHE_EPOCH','v3'),('GITHUB_EVENT_NAME','pull_request'),('GITHUB_EVENT_NAME','workflow_run')]:
            with self.subTest(key=key,value=value),tempfile.TemporaryDirectory() as d:
                env=c.env();env[key]=value
                with self.assertRaises(SystemExit):c.guard(env,Path(d))
                self.assertFalse((Path(d)/'reminder-boundary').exists())
        inputs=c.workflow.get('on',c.workflow.get('true'))['workflow_dispatch']['inputs']
        self.assertTrue(inputs['approved_contract_sha256']['required'])
        self.assertEqual(c.job['env']['APPROVED_CONTRACT_SHA256'],'${{ inputs.approved_contract_sha256 }}')
        self.assertEqual(c.job['env']['CACHE_EPOCH'],'${{ inputs.cache_epoch }}')
        self.assertFalse(any(x.get('continue-on-error') for x in c.job['steps']))
    def test_actual_upload_gate_uses_original_budget_after_any_outcome(self):
        boundary_tests.Contract.setUpClass();c=boundary_tests.Contract()
        gate=c.job['steps'][-2]
        self.assertEqual(gate['if'],'always()')
        self.assertEqual(c.job['steps'][-1]['if'],"${{ always() && steps.evidence.outputs.upload == 'true' }}")
        script=gate['run'].split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]
        for eligible,left in [(True,300),(True,299),(False,400)]:
            with self.subTest(eligible=eligible,left=left),tempfile.TemporaryDirectory() as d:
                top=Path(d);root=top/'reminder-boundary';root.mkdir()
                b.save(root/'budget.json',{'started_monotonic':100})
                if eligible:(root/'upload-eligible').write_text('manifest complete\n')
                output=top/'output'
                env={'RUNNER_TEMP':str(top),'GITHUB_OUTPUT':str(output)}
                with patch.dict(os.environ,env,clear=True),patch.object(time,'monotonic',return_value=3700-left):
                    if eligible and left>=300:exec(compile(script,'actual-upload-guard','exec'),{})
                    else:
                        with self.assertRaises(SystemExit):exec(compile(script,'actual-upload-guard','exec'),{})
                self.assertEqual(output.read_text(),'upload='+str(eligible and left>=300).lower()+'\n')
    def test_exact_existing_pins_and_one_test_call_site(self):
        self.assertEqual(b.XCODEGEN_SHA,'4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806')
        self.assertEqual(b.XCODEGEN_URL,'https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip')
        module=ast.parse(Path(b.__file__).read_text())
        execute=next(n for n in module.body if isinstance(n,ast.FunctionDef) and n.name=='execute')
        calls=[n for n in ast.walk(execute) if isinstance(n,ast.Call)]
        phase=[n.args[0].value for n in calls if isinstance(n.func,ast.Attribute) and n.func.attr=='run'
               and n.args and isinstance(n.args[0],ast.Constant)]
        self.assertEqual(phase.count('xcodebuild-test'),1);self.assertEqual(phase.count('create-simulator'),1)
        self.assertEqual(phase.count('resolve-once'),1)
        self.assertEqual(sum(isinstance(n.func,ast.Name) and n.func.id=='Budget' for n in calls),1)
        self.assertNotIn('finalize_local',ast.unparse(execute))


class Interpretation(unittest.TestCase):
    def combined(self,doc=None,legacy=None,raw=65):
        doc=doc or fixture()
        export={'exported':True,'classification':s.classify(encode(doc),IDENTITY)}
        legacy=legacy if legacy is not None else {'capture_valid':True,'records':copy.deepcopy(doc['events']),
            'actual_cases':[{'nodeIdentifier':b.CASE,'result':'Passed'}]}
        return s.interpret(export,legacy,raw)
    def test_file_positive_log_unseen_overrides_no_legacy_narrative(self):
        v=self.combined(legacy={'capture_valid':False,'records':[],
            'outcome':'pre-binding failure','actual_cases':[{'nodeIdentifier':b.CASE,'result':'Passed'}]})
        self.assertIn('file-positive-log-unseen',v['comparison'])
        self.assertNotIn('pre-binding failure',json.dumps(v))
        self.assertFalse(v['test_nonreproduction']);self.assertEqual(v['raw_test_exit'],65)
        self.assertFalse(v['negative_marker_inference_qualified'])
    def test_matching_positive_prefix_and_nonreproduction_are_separate(self):
        failed=self.combined();self.assertEqual(failed['comparison'],'matching-positive-prefix')
        self.assertFalse(failed['test_nonreproduction']);self.assertEqual(failed['raw_test_exit'],65)
        passed=self.combined(raw=0);self.assertTrue(passed['test_nonreproduction'])
        self.assertFalse(passed['negative_marker_inference_qualified'])
    def test_partial_and_baseline_prefix_never_negative(self):
        for n in (1,2,4):
            d=fixture();d['events']=d['events'][:n];d.update(eventCount=n,lastSequence=n,replacementAttempts=n,
                measuredWrites=n-1,writeNanoseconds=0 if n==1 else 100)
            v=self.combined(doc=d)
            self.assertEqual(v['prefix_extent'],'partial-or-baseline')
            self.assertFalse(v['negative_marker_inference_qualified'])
            if n==1:self.assertIn('baseline-only',v['comparison'])
    def test_invalid_or_absent_file_has_no_positive_inference(self):
        for export in ({'exported':False},{'classification':{'valid':False,'records':fixture()['events']}}):
            v=s.interpret(export,{'capture_valid':False,'outcome':'untrusted'},65)
            self.assertEqual(v['comparison'],'invalid-or-unavailable-prefix');self.assertEqual(v['file_positive_events'],[])
    def test_only_same_clock_six_decimal_tick_rounding_is_allowed(self):
        d=fixture();d['events'][1]['tick']=2.12345649
        logged=copy.deepcopy(d['events']);logged[1]['tick']=2.123456
        v=self.combined(doc=d,legacy={'capture_valid':True,'records':logged})
        self.assertEqual(v['comparison'],'matching-positive-prefix')
        logged[1]['tick']=2.1234571
        v=self.combined(doc=d,legacy={'capture_valid':True,'records':logged})
        self.assertIn('field-difference',v['comparison'])
        logged[1]['tick']=2.123456;logged[1]['enabled']=True
        self.assertIn('field-difference',self.combined(doc=d,legacy={'capture_valid':True,'records':logged})['comparison'])


class RetainedPrefix(unittest.TestCase):
    @unittest.skipUnless(os.environ.get('DW_PREFIX_RETAINED'),'Retained prefix evidence path not supplied')
    def test_exact_validated_local_prefix_and_logger_comparison(self):
        p=Path(os.environ['DW_PREFIX_RETAINED'])
        raw=(p/'snapshot-prefix.raw.json').read_bytes()
        self.assertEqual(b.sha(raw),'7e9b36dfbdccb6e6ae438cf21b328ad3796f67fd720f652b621164f8e71fb5e8')
        identity=b.session_identity((p/'Session.log').read_text())
        file=s.classify(raw,identity)
        self.assertTrue(file['valid']);self.assertEqual(len(file['records']),11)
        self.assertEqual(file['counters']['writeNanoseconds'],5287541)
        self.assertEqual(file['counters']['measuredWrites'],10)
        tests=json.loads((p/'tests.json').read_text())
        legacy=b.validate_capture((p/'app-stdout-stderr.txt').read_text(),(p/'Session.log').read_text(),
            json.loads((p/'summary.json').read_text()),tests,json.loads((p/'test-activities.json').read_text()),
            tests['devices'][0]['deviceId'],True)
        combined=s.interpret({'classification':file},legacy,0)
        self.assertTrue(legacy['capture_valid']);self.assertEqual(combined['comparison'],'matching-positive-prefix')
        self.assertTrue(combined['test_nonreproduction']);self.assertEqual(combined['field_differences'],[])
        self.assertFalse(combined['negative_marker_inference_qualified'])
        # Retained-byte counterfactual, no runtime: positive file cannot be erased by missing Logger tail.
        truncated=copy.deepcopy(legacy);truncated['records']=truncated['records'][:1]
        lost=s.interpret({'classification':file},truncated,65)
        self.assertIn('file-positive-log-unseen',lost['comparison']);self.assertEqual(lost['raw_test_exit'],65)
        self.assertFalse(lost['test_nonreproduction'])
        stdout=(p/'verify-container-interface.stdout').read_bytes()
        stderr=(p/'verify-container-interface.stderr').read_bytes()
        self.assertEqual(b.sha(stderr),'62b5b30225c28644c70945a598f2385b4414e2f11c75c4ec2d134d6822f0053b')
        b.validate_container_help(stdout,stderr,0)

if __name__=='__main__':unittest.main()

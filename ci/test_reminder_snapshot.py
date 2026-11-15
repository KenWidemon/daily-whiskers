"""Offline-only fixtures. All host commands are mocked; no app/simulator run."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import reminder_boundary as b
import reminder_snapshot as s

RUN = '12345678-1234-1234-1234-123456789ABC'
IDENTITY = {'run':RUN,'pid':99}
SESSION = "Test Case '-[DailyWhiskersUITests.ReminderUITests testDiagnosticInitialEnableProbe]' started.\nLaunched app with identifier: com.example.kenwidemon.dailywhiskers (pid = 99)\n\"DW_REMINDER_TEST_ID\" = \""+RUN+'";\n'


def fixture():
    base = dict(schema=1,run=RUN,pid=99,seq=1,tick=1.,stage='ready',id=0,command='none',requested=-1,enabled=False,authorization='notDetermined',queued=0,hasCoverage=False,hasMessage=False,storageBlocked=False,cleanupPending=False,busy=False,loaded=False,operations=0)
    events = [base]
    # Interleaved refresh completes after enable entry, before enable publication.
    for stage,ident,command in [('bindingSetter',0,'enable'),('sendEntry',1,'refresh'),('sendEntry',2,'enable'),('statusPublished',1,'refresh'),('sendComplete',1,'refresh'),('statusPublished',2,'enable'),('sendComplete',2,'enable')]:
        events.append(dict(base,stage=stage,id=ident,operations=-1 if stage=='bindingSetter' else 0,command=command,requested=1 if command=='enable' else -1,seq=len(events)+1,tick=float(len(events)+1)))
    return dict(witnessSchema=1,kind='prefix',run=RUN,pid=99,eventCount=len(events),lastSequence=len(events),replacementAttempts=len(events),overflow=False,measuredWrites=len(events)-1,writeNanoseconds=100,events=events)


def encode(doc):
    return json.dumps(doc).encode()


class Classifier(unittest.TestCase):
    def test_known_interleaving_without_any_log_input(self):
        v=s.classify(encode(fixture()),IDENTITY)
        self.assertTrue(v['valid'],v)
        self.assertTrue(v['observed']['enableComplete'])
        self.assertFalse(v['negative_marker_inference_qualified'])
    def test_stale_identity_and_invalid_bytes(self):
        for raw,identity in [(encode(fixture()),dict(IDENTITY,pid=98)),(encode(fixture()),dict(IDENTITY,run='AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA')),(b'{',IDENTITY),(b' '*65537,IDENTITY),(b'null',IDENTITY),(b'[]',IDENTITY),(b'{"kind":1,"kind":2}',IDENTITY)]:
            with self.subTest(raw=raw[:20],identity=identity):self.assertFalse(s.classify(raw,identity)['valid'])
    def test_exact_types_schema_identity_counters(self):
        mutations=[('witnessSchema',2),('witnessSchema',True),('kind','complete'),('eventCount',7),('lastSequence',9),('replacementAttempts',9),('measuredWrites',8),('overflow',1),('writeNanoseconds',-1),('writeNanoseconds',2**64),('pid',True)]
        for key,value in mutations:
            d=fixture();d[key]=value
            with self.subTest(key=key,value=value):self.assertFalse(s.classify(encode(d),IDENTITY)['valid'])
        for key,value in [('run','AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'),('pid',98),('seq',9),('tick',-1),('tick',True),('schema',True),('authorization','provisional'),('enabled',1),('id',4),('command','none'),('requested',-1)]:
            d=fixture();d['events'][1][key]=value
            with self.subTest(event=key):self.assertFalse(s.classify(encode(d),IDENTITY)['valid'])
    def test_prefix_and_overflow_never_negative(self):
        d=fixture();d['events']=d['events'][:1];d.update(eventCount=1,lastSequence=1,replacementAttempts=1,measuredWrites=0,writeNanoseconds=0)
        v=s.classify(encode(d),IDENTITY);self.assertTrue(v['valid']);self.assertFalse(v['observed']['enableEntry'])
        for n in range(2,65):
            # Many refresh entries are legal interleaving; no completion claim.
            d['events'].append(dict(d['events'][0],seq=n,tick=n,stage='sendEntry',id=n-1,command='refresh'))
        d.update(eventCount=64,lastSequence=64,replacementAttempts=65,measuredWrites=64,writeNanoseconds=100,overflow=True)
        v=s.classify(encode(d),IDENTITY);self.assertTrue(v['valid'],v);self.assertFalse(v['negative_marker_inference_qualified'])
    def test_byte_overflow_can_retain_empty_prefix(self):
        d=fixture();d.update(events=[],eventCount=0,lastSequence=0,replacementAttempts=1,measuredWrites=0,writeNanoseconds=0,overflow=True)
        v=s.classify(encode(d),IDENTITY);self.assertTrue(v['valid'],v);self.assertFalse(v['negative_marker_inference_qualified'])
        d['overflow']=False
        self.assertFalse(s.classify(encode(d),IDENTITY)['valid'])
    def test_operations_unknown_only_at_binding_setter(self):
        d=fixture()
        self.assertEqual(d['events'][1]['operations'],-1)
        self.assertTrue(s.classify(encode(d),IDENTITY)['valid'])
        for i in (0,2,3,4,5,6,7):
            changed=copy.deepcopy(d);changed['events'][i]['operations']=-1
            with self.subTest(index=i):self.assertFalse(s.classify(encode(changed),IDENTITY)['valid'])
        d['events'][1]['operations']=-2
        self.assertFalse(s.classify(encode(d),IDENTITY)['valid'])
    def test_binding_setter_sentinels_preserve_sampled_model_fields(self):
        d=fixture()
        setter=d['events'][1]
        setter.update(enabled=True,authorization='quiet',queued=11,hasCoverage=True,hasMessage=True,
                      storageBlocked=True,cleanupPending=True,busy=True,loaded=True)
        v=s.classify(encode(d),IDENTITY)
        self.assertTrue(v['valid'],v)
        note=v['interpretation']['bindingSetter']
        self.assertEqual(note['operations_minus_one'],'unsampled; not an operation count')
        self.assertEqual(note['id_zero'],'no send-command identity yet')
        self.assertEqual(v['records'][1]['operations'],-1)
        self.assertEqual(v['records'][1]['id'],0)
        for field in note['sampled_model_fields']:
            self.assertEqual(v['records'][1][field],setter[field])
        self.assertTrue(any('Model/status fields are sampled' in text for text in v['limitations']))
    def test_session_independent_identity(self):
        self.assertEqual(b.session_identity(SESSION),IDENTITY)
        for text in ['',SESSION+SESSION,SESSION.replace('pid = 99','pid = 0'),SESSION.replace(RUN,RUN.lower()),SESSION+'"DW_REMINDER_TEST_ID" = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA";']:
            with self.assertRaises((b.Invalid,ValueError)):b.session_identity(text)


class FakeBudget:
    started=0
    left=1000
    def remaining(self,final=False):return self.left


class Host(unittest.TestCase):
    def test_file_safety(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();p=root/'Library/Application Support/ReminderEnableProbe';p.mkdir(parents=True)
            path=p/(RUN+'.json');path.write_bytes(encode(fixture()))
            self.assertEqual(s.read_exact(str(root),RUN,FakeBudget()),path.read_bytes())
            path.unlink();path.symlink_to(root/'absent')
            with self.assertRaises(OSError):s.read_exact(str(root),RUN,FakeBudget())
            path.unlink();path.write_bytes(b'a'*65537)
            with self.assertRaises(b.Invalid):s.read_exact(str(root),RUN,FakeBudget())
            path.unlink();path.mkdir()
            with self.assertRaises(b.Invalid):s.read_exact(str(root),RUN,FakeBudget())
            path.rmdir();p.rmdir();p.symlink_to(root)
            with self.assertRaises(OSError):s.read_exact(str(root),RUN,FakeBudget())
    def test_post_read_deadline_is_checked(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();p=root/'Library/Application Support/ReminderEnableProbe';p.mkdir(parents=True)
            (p/(RUN+'.json')).write_bytes(encode(fixture()))
            budget=FakeBudget()
            original=s.os.read
            def read(fd,count):
                raw=original(fd,count)
                budget.left=s.EXPORT_RESERVE
                return raw
            with patch.object(s.os,'read',side_effect=read),self.assertRaisesRegex(b.Invalid,'post-read deadline'):
                s.read_exact(str(root),RUN,budget)
    def scenario(self, problem=None):
        tmp=tempfile.TemporaryDirectory();self.addCleanup(tmp.cleanup)
        root=Path(tmp.name).resolve();out=root/'evidence';out.mkdir()
        container=root/'container';p=container/'Library/Application Support/ReminderEnableProbe';p.mkdir(parents=True)
        (p/(RUN+'.json')).write_bytes(encode(fixture()))
        calls=[]
        owned={'udid':'owned','name':'diagnostic','deviceTypeIdentifier':b.TYPE,'runtime':b.RUNTIME,'state':'Booted','isAvailable':True}
        class Commands:
            budget=FakeBudget()
            settled=problem!='unsettled'
            def settle(self,deadline):
                calls.append('settle')
                if not self.settled:raise b.Invalid('Unsettled owned group')
            def run(self,name,argv,*args,**kwargs):
                calls.append(name)
                b.require(self.settled,'Unsettled')
                b.require(self.budget.remaining(True)>kwargs.get('reserve',75),'Absolute deadline exhausted')
                if name=='snapshot-container':
                    assert kwargs['reserve']==s.EXPORT_RESERVE
                if problem=='deadline':raise b.Invalid('Absolute deadline exhausted')
                if name=='local-ownership':return encode({'devices':{b.RUNTIME:[] if problem=='ownership' else [owned]}})
                if name=='snapshot-container':
                    if problem=='container':raise b.Invalid('Missing container')
                    if problem=='cancel':raise InterruptedError('Supervisor signal')
                    if problem=='file':(p/(RUN+'.json')).unlink()
                    if problem=='invalid':(p/(RUN+'.json')).write_bytes(b'{')
                    if problem=='symlink':
                        (p/(RUN+'.json')).unlink()
                        (p/(RUN+'.json')).symlink_to(out/'outside')
                    return str(container).encode()+b'\n'
                if name=='local-cleanup-delete':
                    self.assert_export_order=True
                    if problem is None:assert (out/'snapshot-prefix.raw.json').exists()
                if name=='local-cleanup-readback':return encode({'devices':{}})
                return b''
        commands=Commands()
        class Collector:
            output=out
            def launch_identity(self):
                calls.append('session')
                assert self.final_reserve==s.EXPORT_RESERVE
                if problem=='session':raise b.Invalid('Missing Session')
                if problem=='reserve':
                    commands.budget.left=s.EXPORT_RESERVE
                    # A later extraction command must stop at the shared reserve.
                    real=b.Budget(0,clock=lambda:3300-commands.budget.left)
                    real.allowance(60,final=True,reserve=self.final_reserve)
                return b.session_identity(SESSION)
            def collect(self,*args):
                calls.append('ordinary')
                assert getattr(self,'final_reserve',75)==75
                if problem=='stdout':raise b.Invalid('Missing stdout')
                return {'capture_valid':True}
        receipt=s.finalize_local(commands,Collector(),'owned','diagnostic',{},65)
        self.assertEqual(receipt['raw_test_exit'],65)
        return receipt,calls,out
    def test_success_export_before_delete_and_collect(self):
        r,calls,out=self.scenario();self.assertTrue(r['export']['classification']['valid']);self.assertTrue(r['cleanup']['verified'])
        self.assertLess(calls.index('session'),calls.index('snapshot-container'))
        self.assertLess(calls.index('snapshot-container'),calls.index('local-cleanup-delete'))
        self.assertLess(calls.index('local-cleanup-delete'),calls.index('ordinary'))
        self.assertEqual(r['export']['sha256'],b.sha((out/'snapshot-prefix.raw.json').read_bytes()))
    def test_missing_export_does_not_block_cleanup(self):
        for problem in ('session','container','file','cancel','symlink'):
            with self.subTest(problem=problem):
                r,calls,_=self.scenario(problem);self.assertFalse(r['export']['exported']);self.assertTrue(r['cleanup']['verified']);self.assertIn('local-cleanup-delete',calls)
    def test_invalid_export_retains_raw_hash_and_failure_exit(self):
        r,_,out=self.scenario('invalid');self.assertTrue(r['export']['exported']);self.assertFalse(r['export']['classification']['valid'])
        self.assertEqual((out/'snapshot-prefix.raw.json').read_bytes(),b'{')
        self.assertTrue(r['cleanup']['verified'])
    def test_extraction_reserve_exhaustion_still_allows_cleanup(self):
        r,calls,_=self.scenario('reserve')
        self.assertFalse(r['export']['exported'])
        self.assertIn('Absolute deadline exhausted',r['export']['error'])
        self.assertNotIn('snapshot-container',calls)
        self.assertIn('local-cleanup-delete',calls)
        self.assertTrue(r['cleanup']['verified'])
    def test_stdout_absence_does_not_block_export(self):
        r,_,_=self.scenario('stdout');self.assertTrue(r['export']['exported']);self.assertFalse(r['collector']['capture_valid'])
    def test_unsettled_ownership_deadline_forbid_export_delete(self):
        for problem in ('unsettled','ownership','deadline'):
            r,calls,_=self.scenario(problem);self.assertFalse(r['cleanup']['verified']);self.assertNotIn('snapshot-container',calls);self.assertNotIn('local-cleanup-delete',calls)


class SessionCollector(unittest.TestCase):
    def test_session_extraction_without_stdout_and_no_duplicate_extract(self):
        with tempfile.TemporaryDirectory() as d:
            collector=b.Collector(None,Path('/unused.xcresult'),Path(d))
            node={'ref':'diagnostic'}
            dirs=[ [({'type':2,'name':'DailyWhiskersUITests-ABC-Configuration-Test Scheme Action-Iteration-1'}, {'ref':'iteration'})],
                   [({'type':2,'name':'DailyWhiskersUITests-DEF'}, {'ref':'session'})],
                   [({'type':1,'name':'Session-DailyWhiskersUITests-ABC.log'}, {'ref':'session-log'})] ]
            root={'actions':[{'actionResult':{'diagnosticsRef':{'id':'diagnostic'}}}]}
            with patch.object(collector,'obj',side_effect=[root,SESSION.encode()]) as obj, patch.object(collector,'get',return_value=b'graph'), patch.object(collector,'directory',side_effect=dirs), patch.object(b,'parse_graph',return_value=node):
                self.assertEqual(collector.launch_identity(),IDENTITY)
                self.assertEqual(collector.launch_identity(),IDENTITY)
                self.assertEqual(obj.call_count,2)
                self.assertEqual(collector.session_context()[2],[])
                self.assertTrue((Path(d)/'session-provenance.json').exists())
    def test_failed_session_extraction_is_not_retried(self):
        with tempfile.TemporaryDirectory() as d:
            collector=b.Collector(None,Path('/unused'),Path(d))
            with patch.object(collector,'obj',side_effect=b.Invalid('No diagnostics')) as obj:
                for _ in range(2):
                    with self.assertRaises(b.Invalid):collector.launch_identity()
                self.assertEqual(obj.call_count,1)


if __name__=='__main__':unittest.main()

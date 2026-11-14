"""One real sample of an owned synthetic child. Never app acceptance."""
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time
import traceback
import uuid
from launch_observation import run_sampler, stop_worker

ROOT=Path(__file__).resolve().parent.parent
TARGET='''import json,os,signal,sys,time
print(json.dumps({'pid':os.getpid(),'parent_pid':os.getppid(),'nonce':sys.argv[1],'executable':sys.executable,'started':time.time()}),flush=True)
def end(*args):
 print('synthetic-target-terminated',flush=True)
 raise SystemExit(0)
signal.signal(signal.SIGTERM,end)
time.sleep(30)
raise SystemExit(24)
'''

def save(path,value):path.write_text(json.dumps(value,indent=2))
def stamp():return {'utc_epoch':time.time(),'monotonic_ns':time.monotonic_ns()}
def require(value,message):
    if not value:raise ValueError(message)


def inspect_sample(raw,pid,parent):
    require(0<len(raw)<=32*1024*1024,'Missing or oversized sample')
    text=raw.decode('utf-8','replace')
    require(re.search(r'^Process:\s+.+\['+str(pid)+r'\]\s*$',text,re.M),'Wrong sample target PID')
    require(re.search(r'^Parent Process:\s+.+\['+str(parent)+r'\]\s*$',text,re.M),'Wrong sample parent PID')
    require('Call graph:' in text,'No call graph')
    graph=text.split('Call graph:',1)[1].split('Total number in stack',1)[0].split('Binary Images:',1)[0]
    require(re.search(r'Thread_\d+',graph),'No sampled thread')
    frames=re.findall(r'^\s*[+!:| ]*\d+\s+[^\n]+\(in [^)]+\)[^\n]*$',graph,re.M)
    require(len(frames)>=2,'No usable symbol/image stack frames')
    return {'pid':pid,'parent_pid':parent,'frame_lines':len(frames),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'scope':'synthetic process stacks only'}


def worker(payload,offline=None):
    d=Path(payload['directory']);record={'started':stamp(),'pid':os.getpid(),'payload':payload,'status':'entered','offline_stub':offline}
    signal.signal(signal.SIGALRM,lambda *_:os.killpg(os.getpgrp(),signal.SIGKILL))
    signal.setitimer(signal.ITIMER_REAL,4.0)
    try:
        save(d/'observer.json',record)
        sample=d/'sample.txt'
        command=['/usr/bin/sample',str(payload['target_pid']),'1','10','-file',str(sample)]
        if offline:
            body='Process: Python ['+str(payload['target_pid'])+']\nParent Process: Python ['+str(payload['parent_pid'])+']\nCall graph:\n    10 Thread_1\n    + 10 sleep (in libsystem_kernel.dylib) + 1\n    + 10 PyEval (in Python) + 2\n'
            if offline=='bad':body='header only'
            code='from pathlib import Path;Path('+repr(str(sample))+').write_text('+repr(body)+')'
            if offline=='stuck':code='import time;time.sleep(30)'
            command=[sys.executable,'-B','-c',code]
        record['command']=command;record['sample_started']=stamp();save(d/'observer.json',record)
        with (d/'sampler-output.raw').open('wb') as output:
            exit_code=run_sampler(command,output,time.monotonic()+3.5,d/'sampler-lifecycle.json')
        record['sample_finished']=stamp();record['sampler_exit']=exit_code
        require(exit_code==0,'Sampler nonzero exit')
        record['sample']=inspect_sample(sample.read_bytes(),payload['target_pid'],payload['parent_pid'])
        record['status']='captured-synthetic'
        return 0
    except Exception as error:
        record.update(status='failed',error=repr(error));traceback.print_exc();return 1
    finally:
        record['finished']=stamp();save(d/'observer.json',record)


def cleanup_target(child):
    result={'pid':child.pid,'started':stamp()}
    # This is our exact owned child; no discovery or inspection of other processes.
    early=child.poll();result['premature_exit']=early
    if early is None:
        try:child.terminate();result['signal']='SIGTERM sent'
        except OSError as error:result['signal_error']=repr(error)
        try:result['exit']=child.wait(timeout=.5)
        except subprocess.TimeoutExpired:
            try:child.kill();result['escalation']='SIGKILL sent'
            except OSError as error:result['kill_error']=repr(error)
            try:result['exit']=child.wait(timeout=.5)
            except (OSError,subprocess.SubprocessError) as error:result['reap_error']=repr(error)
        except OSError as error:result['reap_error']=repr(error)
    else:result['exit']=early
    result['reaped']=child.returncode is not None;result['finished']=stamp()
    return result


def smoke(directory,offline=None):
    directory.mkdir(parents=True,exist_ok=False)
    record={'started':stamp(),'offline_stub':offline,'passed':False,'source_sha':os.environ.get('GITHUB_SHA','local'),
      'expected_source_sha':os.environ.get('EXPECTED_SOURCE_SHA'),'python':sys.version,'executable':sys.executable,'cwd':os.getcwd(),
      'runner':{k:os.environ.get(k) for k in ('RUNNER_NAME','RUNNER_OS','RUNNER_ARCH','ImageOS','ImageVersion')},
      'hashes':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(list((ROOT/'ci').glob('*.py'))+list((ROOT/'.github/workflows').glob('*.yml')))}}
    target=None;observer=None;failure=None
    try:
        save(directory/'identity.json',record)
        nonce=uuid.uuid4().hex
        with (directory/'target-stderr.raw').open('wb') as stderr:
            target=subprocess.Popen([sys.executable,'-B','-c',TARGET,nonce],stdout=subprocess.PIPE,stderr=stderr)
        record['target_creation']={'pid':target.pid,'parent_pid':os.getpid(),'nonce':nonce,'created':stamp()}
        save(directory/'target-creation.json',record['target_creation'])
        with selectors.DefaultSelector() as selector:
            selector.register(target.stdout,selectors.EVENT_READ)
            require(selector.select(timeout=2),'Synthetic target startup timeout')
            raw=os.read(target.stdout.fileno(),65536)
        (directory/'target-stdout.raw').write_bytes(raw)
        ready=json.loads(raw);require(ready['pid']==target.pid and ready['parent_pid']==os.getpid() and ready['nonce']==nonce,'Target ownership mismatch')
        record['target_ready']=ready
        payload={'target_pid':target.pid,'parent_pid':os.getpid(),'directory':str(directory),'nonce':nonce}
        command=[sys.executable,'-B',str(Path(__file__).resolve()),'--worker',json.dumps(payload)]
        if offline:command+=['--offline',offline]
        record['observer_spawn']=stamp()
        with (directory/'observer-stderr.raw').open('wb') as log:
            observer=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        record['observer_pid']=observer.pid
        try:
            code=observer.wait(timeout=4)
            record['observer_termination']={'exit':code,'reaped':True,'mode':'normal-wait','finished':stamp()}
        except subprocess.TimeoutExpired:
            record['observer_termination']=stop_worker(observer)
            raise ValueError('Observer watchdog expired')
        elapsed=(time.monotonic_ns()-record['observer_spawn']['monotonic_ns'])/1e9
        record['observer_elapsed_seconds']=elapsed
        require(code==0 and elapsed<=5,'Observer exit or time bound failed')
        receipt=json.loads((directory/'observer.json').read_text())
        lifecycle=json.loads((directory/'sampler-lifecycle.json').read_text())
        require(receipt['status']=='captured-synthetic' and lifecycle.get('reaped') is True and lifecycle.get('exit_code')==0,'Sampler receipt/reap failed')
        record['sample']=inspect_sample((directory/'sample.txt').read_bytes(),target.pid,os.getpid())
        require(receipt['sample']['sha256']==record['sample']['sha256'],'Sample receipt mismatch')
    except Exception as error:
        failure=repr(error);record['error']=failure;traceback.print_exc()
    finally:
        if observer is not None and observer.returncode is None:
            try:record['observer_final_cleanup']=stop_worker(observer)
            except (OSError,subprocess.SubprocessError) as error:
                failure=repr(error);record['observer_cleanup_error']=failure
        if target is not None:
            record['target_cleanup']=cleanup_target(target)
            # Read only after confirmed reap to avoid indefinite pipe waiting.
            if target.returncode is not None:
                with (directory/'target-stdout.raw').open('ab') as output:output.write(target.stdout.read())
                target.stdout.close()
        record['finished']=stamp()
        cleanup=record.get('target_cleanup',{})
        record['passed']=failure is None and cleanup.get('reaped') is True and cleanup.get('exit')==0 and cleanup.get('premature_exit') is None and not cleanup.get('signal_error') and not cleanup.get('kill_error')
        rawpath=directory/'target-stdout.raw'
        if rawpath.exists():
            raw=rawpath.read_bytes();record['raw_stdout']={'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
            record['passed']=record['passed'] and raw.endswith(b'synthetic-target-terminated\n')
        save(directory/'result.json',record)
    return 0 if record['passed'] else 1


if __name__=='__main__':
    offline=sys.argv[-1] if '--offline' in sys.argv else None
    if offline not in (None,'good','bad','stuck'):raise SystemExit(2)
    if sys.argv[1]=='--worker':raise SystemExit(worker(json.loads(sys.argv[2]),offline))
    raise SystemExit(smoke(Path(sys.argv[1]).resolve(),offline))

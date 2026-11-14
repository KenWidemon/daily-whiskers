"""Synthetic hosted harness preflight, never an app or real-sampler acceptance gate."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import sys
import time
import traceback
import unittest

ROOT = Path(__file__).resolve().parent.parent
LINE = b'    t = 1.00s Launch com.example.kenwidemon.dailywhiskers\n'
RAW = b'synthetic-prefix\x00\xff\n' + LINE + b'synthetic-tail\x00\xfe\n'


def save(path, value):
    path.write_text(json.dumps(value, indent=2))


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def scenario(name, directory):
    import launch_observation as observer
    directory.mkdir(parents=True)
    fixture = directory / 'fixture'
    fixture.mkdir()
    shutil.copyfile(ROOT/'ci/launch_capture_bootstrap.py', fixture/'launch_capture_bootstrap.py')
    source = ROOT/'ci/launch_observation.py'
    # The unchanged real bootstrap imports a script-adjacent shim in a fresh
    # interpreter. The shim loads the exact repaired source; only observation
    # inputs/tools are replaced. No real snapshot or sample tool can be reached.
    shim = '''import importlib.util, json, pathlib, sys, time
spec=importlib.util.spec_from_file_location('repaired_observer', SOURCE)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
print('synthetic observer entered',file=sys.stderr,flush=True)
m.snapshot=lambda pid,until: 'synthetic exact-owned child; no process inspection'
original_sampler=m.run_sampler
def sampler(command, output, until, path):
    sample=pathlib.Path(command[-1])
    body='Process: xcodebuild ['+command[1]+']\\nSYNTHETIC STACK ONLY\\n'
    stub=[sys.executable,'-B','-c','from pathlib import Path;Path('+repr(str(sample))+').write_text('+repr(body)+')']
    return original_sampler(stub,output,until,path)
m.run_sampler=sampler
observe=m.observe
'''.replace('SOURCE', repr(str(source)))
    if name == 'import-failure':
        shim = "raise ImportError('synthetic import failure')\n"
    elif name == 'stuck-worker':
        shim += '\ndef observe(*args):\n print("synthetic stuck worker",file=sys.stderr,flush=True)\n time.sleep(30)\n'
    (fixture/'launch_observation.py').write_text(shim)
    observer.__file__ = str(fixture/'launch_observation.py')
    with (directory/'selected-stderr.raw').open('wb') as stderr:
        child = subprocess.Popen([sys.executable,'-B','-c',
            'import os;os.write(1,'+repr(RAW)+');raise SystemExit(65)'],
            stdout=subprocess.PIPE, stderr=stderr)
        launch = {'pid':child.pid,'command':['xcodebuild','SYNTHETIC-NOT-EXECUTED'],
                  'deadline':time.time()+20,'synthetic':True,'source':str(source)}
        save(directory/'launch.json', launch)
        code, report = observer.forward(child, launch, directory)
    save(directory/'exit.json', {'actual_selected_exit':code,'synthetic':True,'capture':report})
    require(code == 65, 'Selected child exit was replaced')
    require((directory/'stdout.raw').read_bytes() == RAW, 'Child raw bytes changed')
    require(report['sha256'] == hashlib.sha256(RAW).hexdigest(), 'Raw digest mismatch')
    require(not report['errors'] and not report['downstream_broken'], 'Capture errors')
    require(report['worker_identity']['status'] == 'spawned', 'Spawn not evidenced')
    termination = report['worker_termination']
    require(termination['reaped'] is True, 'Worker reap unverified')
    bootstrap = report['bootstrap']
    require(bootstrap['pid'] == report['worker_identity']['pid'], 'Bootstrap PID mismatch')
    require((directory/'observer-stderr.log').is_file(), 'Missing stderr')
    if name == 'success':
        require(bootstrap['status']=='returned' and termination['worker_exit_code']==0, 'Worker failed')
        final=json.loads((directory/'host-observation.json').read_text())
        require(report['worker_final_receipt']=='present' and final['status']=='captured-unqualified', 'Missing synthetic final receipt')
        lifecycle=json.loads((directory/'sampler-lifecycle.json').read_text())
        require(lifecycle['reaped'] and lifecycle['exit_code']==0, 'Stub sampler lifecycle failed')
        require(b'SYNTHETIC STACK ONLY' in (directory/'host-xcodebuild.sample.txt').read_bytes(), 'Missing stub bytes')
    elif name == 'import-failure':
        require(bootstrap['status']=='error' and termination['worker_exit_code']==1, 'Import failure not retained')
        require('synthetic import failure' in report['worker_stderr']['excerpt'], 'Lost import stderr')
        require(report['worker_final_receipt']=='missing-or-incomplete', 'Unexpected final receipt')
    else:
        require(bootstrap['status']=='imported' and termination['worker_exit_code']==-signal.SIGKILL, 'Stuck worker not bounded/reaped')
        require('synthetic stuck worker' in report['worker_stderr']['excerpt'], 'Lost stuck stderr')
        require(report['worker_final_receipt']=='missing-or-incomplete', 'Unexpected final receipt')
    save(directory/'scenario-result.json', {'passed':True,'scenario':name,'synthetic':True,
         'limits':'No actual app, real sample permissions, or pre-expiry validity established'})


def suite(name, expected, output):
    tests=unittest.defaultTestLoader.discover(str(ROOT/'ci'),pattern=name+'.py')
    result=unittest.TextTestRunner(verbosity=2).run(tests)
    value={'suite':name,'count':result.testsRun,'expected':expected,'failures':len(result.failures),
           'errors':len(result.errors),'skipped':len(result.skipped)}
    save(output,value)
    return result.wasSuccessful() and result.testsRun==expected and not result.skipped


def main(output):
    output.mkdir(parents=True,exist_ok=False)
    identity={'source_sha':os.environ.get('GITHUB_SHA','local-unpublished'),
              'expected_source_sha':os.environ.get('EXPECTED_SOURCE_SHA'),
              'runner':{k:os.environ.get(k) for k in ('RUNNER_NAME','RUNNER_OS','RUNNER_ARCH','ImageOS','ImageVersion')},
              'python':sys.version,'executable':sys.executable,'platform':platform.platform(),
              'cwd':os.getcwd(),'script':str(Path(__file__).resolve()),'sys_path':sys.path,'synthetic_only':True,
              'hashes':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in sorted(list((ROOT/'ci').glob('*.py'))+list((ROOT/'.github/workflows').glob('*.yml')))}}
    save(output/'identity.json',identity)
    passed=True
    cases=[('suite',n,c) for n,c in [('test_observer_receipts',17),('test_launch_observation',14),('test_diagnostic_postrun',21)]]
    cases += [('scenario',n,0) for n in ('success','import-failure','stuck-worker')]
    results=[]
    for kind,name,count in cases:
        command=[sys.executable,'-B',str(Path(__file__).resolve()),'--'+kind,name,str(output/name)]
        if kind=='suite':command.append(str(count))
        started=time.time()
        with (output/(name+'.stdout.raw')).open('wb') as stdout,(output/(name+'.stderr.raw')).open('wb') as stderr:
            child=subprocess.Popen(command,stdout=stdout,stderr=stderr,start_new_session=True)
            try:
                code=child.wait(timeout=90 if kind=='suite' else 12)
                timed_out=False
            except subprocess.TimeoutExpired:
                os.killpg(child.pid,signal.SIGKILL)
                child.wait(timeout=2)
                code=child.returncode;timed_out=True
        valid=code==0 and not timed_out
        if kind=='scenario' and valid:
            valid=(output/(name+'.stdout.raw')).read_bytes()==RAW
        results.append({'kind':kind,'name':name,'exit':code,'timeout':timed_out,'passed':valid,
                        'started':started,'finished':time.time()})
        passed=passed and valid
        save(output/'summary.json',{'passed':passed,'complete':len(results)==len(cases),'cases':results,
                                  'synthetic_only':True,'retry':False})
        if timed_out:break
    return 0 if passed and len(results)==len(cases) else 1


if __name__=='__main__':
    try:
        if sys.argv[1]=='--scenario':
            scenario(sys.argv[2],Path(sys.argv[3]).resolve());code=0
        elif sys.argv[1]=='--suite':
            code=0 if suite(sys.argv[2],int(sys.argv[4]),Path(sys.argv[3]+'.json')) else 1
        else:code=main(Path(sys.argv[1]).resolve())
    except Exception:
        traceback.print_exc();code=1
    raise SystemExit(code)

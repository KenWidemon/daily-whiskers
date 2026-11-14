"""Minimal worker entry receipt before importing the observation implementation.

Parent retains stderr and its own spawn/reap receipts even if this file cannot run.
"""
import json
import os
from pathlib import Path
import signal
import sys
import time
import traceback


def persist(path, record):
    try:
        path.write_text(json.dumps(record, indent=2))
        return True
    except OSError as error:
        print('bootstrap receipt persistence failed: '+repr(error),file=sys.stderr,flush=True)
        return False


def main(payload):
    directory=Path(payload['directory'])
    path=directory/'observer-bootstrap.json'
    record={'schema':'observer-bootstrap-v1','pid':os.getpid(),'parent_pid':os.getppid(),
            'group':os.getpgrp(),'started':time.time(),'started_monotonic_ns':time.monotonic_ns(),
            'identity':payload['launch'],'status':'entered','errors':[]}
    def alarm(signum,frame):
        # Do not attempt disk I/O here: it could defeat the independent deadline.
        os.killpg(os.getpgrp(),signal.SIGKILL)
    signal.signal(signal.SIGALRM,alarm)
    signal.setitimer(signal.ITIMER_REAL,max(0.001,min(4.0,payload['launch']['deadline']-time.time())))
    try:
        if not persist(path,record):
            raise OSError('Startup receipt unavailable; no sampling attempted')
        from types import SimpleNamespace
        import launch_observation
        record['imported']=time.time()
        record['status']='imported'
        if not persist(path,record):raise OSError('Import receipt unavailable; no sampling attempted')
        launch_observation.observe(SimpleNamespace(pid=payload['launch']['pid']),payload['launch'],directory,payload['line'],payload['received'])
        record['status']='returned'
        return 0
    except Exception as error:
        record['status']='error'
        record['errors'].append({'type':type(error).__name__,'message':str(error)[:4096]})
        traceback.print_exc(file=sys.stderr)
        sys.stderr.flush()
        return 1
    finally:
        record.update(finished=time.time(),finished_monotonic_ns=time.monotonic_ns())
        # Keep alarm armed until process exit, including final evidence persistence.
        if not persist(path,record):
            return 1

if __name__=='__main__':
    if len(sys.argv)!=3 or sys.argv[1]!='--capture':raise SystemExit(2)
    raise SystemExit(main(json.loads(sys.argv[2])))

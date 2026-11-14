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


def ready_main(fd, preparation):
    """Private one-shot handshake; all imports and readiness precede app creation."""
    import socket
    import threading
    import math
    from types import SimpleNamespace
    def uptime_ns():
        if sys.platform!='darwin' or not hasattr(time,'CLOCK_UPTIME_RAW'):
            raise RuntimeError('Shared Darwin uptime clock unavailable')
        return time.clock_gettime_ns(time.CLOCK_UPTIME_RAW)
    channel=socket.socket(fileno=fd)
    channel.set_inheritable(False)
    directory=Path(preparation['directory'])
    path=directory/'observer-bootstrap.json'
    record={'schema':'observer-bootstrap-v1','clock_domain':'darwin.CLOCK_UPTIME_RAW','pid':os.getpid(),'parent_pid':os.getppid(),
        'group':os.getpgrp(),'started':time.time(),'started_monotonic_ns':uptime_ns(),
        'nonce':preparation['nonce'],'preparation':preparation,'status':'entered','errors':[]}
    def abort(signum=None, frame=None):
        # Independent bound, including stuck persistence/imports/descendants.
        os.killpg(os.getpgrp(),signal.SIGKILL)
    def arm(until):
        remaining=until-uptime_ns()/1e9
        if remaining<=0:raise TimeoutError('Absolute observer deadline expired')
        signal.setitimer(signal.ITIMER_REAL,remaining)
    def save():
        if not persist(path,record):raise OSError('Bootstrap persistence failed')
    signal.signal(signal.SIGALRM,abort)
    code=1
    try:
        arm(preparation['startup_deadline_monotonic_ns']/1e9)
        save()
        import launch_observation as observation
        record['imported']=time.time();record['status']='imported';save()
        if not (preparation['clock_domain']==observation.CLOCK_DOMAIN and preparation['parent_pid']==os.getppid() and preparation['source']==observation.source_identity()
                and type(preparation['nonce']) is str and len(preparation['nonce'])==64):
            raise ValueError('Preparation source/parent/nonce mismatch')
        ready={'status':'ready','clock_domain':observation.CLOCK_DOMAIN,'preparation':preparation,'pid':os.getpid(),'parent_pid':os.getppid(),
            'group':os.getpgrp(),'ready_wall':time.time(),'ready_monotonic_ns':uptime_ns()}
        # Acknowledgement is only sent after both durable ready records succeed.
        if not persist(directory/'observer-ready.json',ready):raise OSError('Ready persistence failed')
        record.update(status='ready',ready=ready);save()
        observation.send_once(channel,ready)
        arm(preparation['idle_deadline_monotonic_ns']/1e9)
        message=observation.receive_frame(channel,preparation['idle_deadline_monotonic_ns']/1e9)
        until_ns=message['deadline_monotonic_ns'];until=until_ns/1e9;received=message['received'];launch=message['launch']
        if not (received['clock_domain']==observation.CLOCK_DOMAIN and message['kind']=='trigger' and message['preparation']==preparation and message['worker_pid']==os.getpid()
                and type(until_ns) is int and type(received['monotonic_ns']) is int
                and received['monotonic_ns'] < until_ns <= received['monotonic_ns']+4_000_000_000
                and until<=preparation['idle_deadline_monotonic_ns']/1e9 and uptime_ns()/1e9<until
                and launch['observer_deadline_monotonic_ns']==until_ns and launch['observer_preparation']==preparation
                and launch['parent_pid']==preparation['parent_pid'] and type(launch['pid']) is int and launch['pid']>0
                and all(launch.get(k)==v for k,v in preparation['context'].items())
                and launch['started']>=ready['ready_wall']
                and observation.PATTERN.fullmatch(message['line'].encode('ascii'))):
            raise ValueError('Invalid/expired/mismatched trigger')
        arm(until)  # Original absolute parent deadline, never receive+4.
        record.update(status='triggered',identity=launch,trigger_deadline_monotonic_ns=until_ns,
                      trigger_received_monotonic_ns=uptime_ns());save()
        # Blocking private EOF watcher, not process polling. Parent endpoint is
        # never inherited by app/worker/sampler. Any further bytes are forbidden.
        channel.settimeout(None)
        def watch_parent():
            try:channel.recv(1)
            finally:abort()
        threading.Thread(target=watch_parent,daemon=True).start()
        observation.observe(SimpleNamespace(pid=launch['pid']),launch,directory,message['line'],received)
        record['status']='returned';code=0
    except Exception as error:
        # Bound failure evidence persistence after EOF/malformed input as well.
        signal.setitimer(signal.ITIMER_REAL,0.75)
        record['status']='error';record['errors'].append({'type':type(error).__name__,'message':str(error)[:4096]})
        traceback.print_exc(file=sys.stderr);sys.stderr.flush()
    finally:
        record.update(finished=time.time(),finished_monotonic_ns=uptime_ns())
        if not persist(path,record):code=1
        # Do not close the watched endpoint before process exit. Alarm remains
        # armed through final persistence and interpreter shutdown.
    return code


if __name__=='__main__':
    if len(sys.argv)==4 and sys.argv[1]=='--ready':
        raise SystemExit(ready_main(int(sys.argv[2]),json.loads(sys.argv[3])))
    if len(sys.argv)!=3 or sys.argv[1]!='--capture':raise SystemExit(2)
    raise SystemExit(main(json.loads(sys.argv[2])))

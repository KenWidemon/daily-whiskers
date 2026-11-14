"""One-shot exact-child observation; stdout forwarding is potential perturbation.

Capture times are NOT proof of pre-expiry validity. Correlate raw Session logs.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import selectors
import signal
import sys
import time

SCHEMA = 'owned-launch-observation-v1'
LIMIT = 4096
PATTERN = re.compile(rb'^\s*t =\s*([0-9]+(?:\.[0-9]+)?)s\s+Launch com\.example\.kenwidemon\.dailywhiskers\s*$')

class Trigger:
    def __init__(self):
        self.buffer = b''
        self.discard = False
        self.fired = False
        self.long_lines = 0

    def feed(self, chunk):
        found = None
        for part in chunk.splitlines(keepends=True):
            self.buffer += part
            complete = self.buffer.endswith(b'\n')
            if len(self.buffer) > LIMIT:
                if not self.discard:
                    self.long_lines += 1
                self.discard = True
                self.buffer = b''
            if complete:
                if not self.discard and not self.fired and PATTERN.fullmatch(self.buffer.rstrip(b'\r\n')):
                    self.fired = True
                    found = self.buffer.decode('ascii').rstrip()
                self.buffer = b''
                self.discard = False
        return found


def write(path, value):
    path.write_text(json.dumps(value, indent=2))


def snapshot(pid, until):
    # Exact child PID, never a process-name query or discovery scan.
    value = subprocess.check_output(['/bin/ps', '-p', str(pid), '-o', 'pid=,ppid=,stat=,comm='],
                                    text=True, stderr=subprocess.PIPE,
                                    timeout=max(0.001, until-time.monotonic()))
    fields = value.strip().split(None, 3)
    if len(fields) != 4 or int(fields[0]) != pid or int(fields[1]) != int(os.environ.get('OBSERVATION_OWNER_PID', os.getpid())) or 'Z' in fields[2] or Path(fields[3]).name != 'xcodebuild':
        raise ValueError('Owned live xcodebuild identity unavailable or mismatched')
    return value.strip()


def run_sampler(command, output, until, path):
    """Retain primary failure, signal uncertainty and bounded reap independently."""
    record={'schema':'sampler-lifecycle-v1','command':command,'status':'planned',
            'parent_pid':os.getpid(),'group':os.getpgrp(),'started':time.time(),
            'started_monotonic_ns':time.monotonic_ns(),'deadline_monotonic':until}
    write(path,record)
    child=None
    primary=None
    try:
        child=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT)
        record.update(status='spawned',pid=child.pid,spawn_returned=time.time())
        write(path,record)
        record['exit_code']=child.wait(timeout=max(0.001,until-time.monotonic()))
        record['reaped']=True
        record['status']='returned'
    except (OSError,subprocess.SubprocessError) as error:
        primary=error
        record['primary_error']=f'{type(error).__name__}: {error}'
    finally:
        if child is not None and not record.get('reaped'):
            record['cleanup_requested']=time.time()
            try:
                child.kill()
                record['signal_result']='sent'
            except OSError as error:
                record['signal_result']='unverified'
                record['signal_error']=f'{type(error).__name__}: {error}'
            try:
                record['exit_code']=child.wait(timeout=0.25)
                record['reaped']=True
            except (OSError,subprocess.SubprocessError) as error:
                record['reaped']=False
                record['reap_error']=f'{type(error).__name__}: {error}'
                record['error']='Sampler reap unverified; observer-group watchdog remains active'
        record.update(finished=time.time(),finished_monotonic_ns=time.monotonic_ns())
        try:write(path,record)
        except OSError as error:
            print('sampler final receipt persistence failed: '+repr(error),file=sys.stderr,flush=True)
            if primary is None:primary=error
    if primary is not None:raise primary
    return record['exit_code']


def observe(process, launch, directory, line, received=None, now=time.monotonic):
    start = now()
    remaining = min(5.0, launch['deadline']-time.time())
    receipt = dict(schema=SCHEMA, identity={k:v for k,v in launch.items() if k not in ('command',)},
                   pid=process.pid, command=launch['command'], trigger=line, trigger_receipt=received,
                   started=time.time(), started_monotonic_ns=time.monotonic_ns(),
                   maximum_seconds=5, duration_seconds=1, interval_milliseconds=10,
                   pre_expiry='unverified: requires raw Session request timing', status='inconclusive')
    path = directory/'host-observation.json'
    write(path,receipt)
    try:
        if process.pid != launch['pid'] or Path(launch['command'][0]).name != 'xcodebuild' or remaining <= 0:
            raise ValueError('Wrong child or exhausted shared deadline')
        until = start + remaining
        receipt['identity_before'] = snapshot(process.pid,until)
        sample = directory/'host-xcodebuild.sample.txt'
        # The direct child is not reaped until the observer is reaped, preventing PID reuse.
        command = ['/usr/bin/sample', str(process.pid), '1', '10', '-file', str(sample)]
        receipt['sample_command'] = command
        with (directory/'sample-command.log').open('wb') as output:
            code = run_sampler(command, output, until, directory/'sampler-lifecycle.json')
        receipt['sample_exit'] = code
        if code != 0 or now() > until or not sample.is_file() or not 0 < sample.stat().st_size <= 32*1024*1024:
            raise ValueError('Failed, late, missing or oversized sample')
        raw = sample.read_bytes()
        # sample embeds its target identity; bind to the launch child, not just filename.
        if not re.search(rb'^Process:\s+xcodebuild\s+\['+str(process.pid).encode()+rb'\]',raw,re.M):
            raise ValueError('Sample target identity mismatch')
        receipt.update(status='captured-unqualified', stack_content='unreviewed: inspect actual stack frames before interpreting', bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
    except (OSError,ValueError,subprocess.SubprocessError) as error:
        receipt['error'] = f'{type(error).__name__}: {error}'[:4096]
    receipt.update(finished=time.time(), finished_monotonic_ns=time.monotonic_ns(), elapsed_seconds=now()-start)
    if receipt['elapsed_seconds'] > 5:
        receipt.update(status='inconclusive',error='Observation exceeded five-second bound')
    write(path,receipt)


def stop_worker(worker):
    """Record signal/reap observations, without claiming an inferred exit cause."""
    if worker is None:return None
    report={'pid':worker.pid,'group':worker.pid,'cleanup_requested':time.time(),
            'cleanup_requested_monotonic_ns':time.monotonic_ns(),'signal':'SIGKILL'}
    try:
        os.killpg(worker.pid,signal.SIGKILL)
        report['signal_result']='sent'
    except ProcessLookupError:
        report['signal_result']='group-absent'
    except OSError as error:
        report['signal_result']='unverified'
        report['signal_error']=f'{type(error).__name__}: {error}'
    try:
        report['worker_exit_code']=worker.wait(timeout=0.75)
        report['reaped']=True
    except subprocess.TimeoutExpired:
        report['reaped']=False
        report['error']='Worker did not reap within reserved 0.75 seconds'
    report.update(finished=time.time(),finished_monotonic_ns=time.monotonic_ns())
    return report


def handle_interruption(worker, signum, directory):
    """Best-effort durable termination evidence; never swallow original signal."""
    record={'schema':'observer-interruption-v1','signal':signum,'started':time.time(),
            'started_monotonic_ns':time.monotonic_ns()}
    try:
        try:record['termination']=stop_worker(worker)
        except (OSError,subprocess.SubprocessError) as error:
            record['cleanup_error']=f'{type(error).__name__}: {error}'
        record.update(finished=time.time(),finished_monotonic_ns=time.monotonic_ns())
        try:write(directory/'observer-interruption.json',record)
        except OSError as error:
            print('interruption receipt persistence failed: '+repr(error),file=sys.stderr,flush=True)
    finally:
        signal.signal(signum,signal.SIG_DFL)
        os.kill(os.getpid(),signum)


def forward(process, launch, directory):
    trigger = Trigger()
    worker = None
    worker_until = None
    errors = []
    observation = 'not-triggered'
    worker_identity = None
    raw = None
    digest = hashlib.sha256()
    total = 0
    broken = False
    previous = {}
    worker_log = None
    worker_termination = None
    def error(operation, exc):
        if len(errors) < 16:
            errors.append({'operation': operation, 'error': f'{type(exc).__name__}: {exc}'[:512]})
    def interrupted(signum, frame):
        handle_interruption(worker,signum,directory)
    def expire_worker():
        nonlocal worker, observation, worker_termination
        if worker is not None and time.monotonic() >= worker_until:
            try:
                worker_termination = stop_worker(worker)
                observation = 'reaped' if worker_termination['reaped'] and worker_termination['signal_result'] != 'unverified' else 'cleanup-unverified'
                try: write(directory/'observer-termination.json',worker_termination)
                except OSError as exc:error('termination-receipt',exc)
            except (OSError, subprocess.SubprocessError) as exc:
                observation = 'cleanup-unverified'
                error('observer-cleanup', exc)
            worker = None
    try:
        for sig in (signal.SIGTERM,signal.SIGINT):
            previous[sig]=signal.signal(sig,interrupted)
        try:
            raw=(directory/'stdout.raw').open('wb')
        except OSError as exc:
            error('raw-open',exc)
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout,selectors.EVENT_READ)
            while selector.get_map():
                expire_worker()
                for key,_ in selector.select(timeout=0.025):
                    try:
                        chunk=os.read(key.fileobj.fileno(),65536)
                    except OSError as exc:
                        error('stream-read',exc)
                        try:
                            chunk=key.fileobj.read1(65536)
                        except OSError as fallback:
                            error('stream-read-fallback',fallback)
                            # Do not close a live child's output pipe or substitute
                            # an observer exit code. The original shared watchdog
                            # remains the stop boundary for irrecoverable I/O.
                            continue
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    digest.update(chunk); total+=len(chunk)
                    if raw is not None:
                        try:
                            raw.write(chunk); raw.flush()
                        except OSError as exc:
                            error('raw-write-or-flush',exc)
                            try: raw.close()
                            except OSError as close_error: error('raw-close',close_error)
                            raw=None
                    if not broken:
                        try:
                            view=memoryview(chunk)
                            while view:
                                sent=os.write(1,view)
                                if sent<=0: raise BrokenPipeError('stdout made no progress')
                                view=view[sent:]
                        except OSError as exc:
                            error('downstream',exc);broken=True
                    line=trigger.feed(chunk)
                    if line is not None:
                        received={'wall_time':time.time(),'monotonic_ns':time.monotonic_ns()}
                        worker_until=time.monotonic()+min(4.0,max(0.0,launch['deadline']-time.time()))
                        try:
                            payload=json.dumps({'launch':launch,'directory':str(directory),'line':line,'received':received})
                            worker_identity={'status':'spawn-requested','started':time.time(),'started_monotonic_ns':time.monotonic_ns(),
                                'trigger_receipt':received,'target_launch':launch,'deadline_monotonic':worker_until,'kill_reserve_seconds':0.75}
                            write(directory/'observer-parent.json',worker_identity)
                            worker_log=(directory/'observer-stderr.log').open('wb')
                            worker=subprocess.Popen([sys.executable,'-B',str(Path(__file__).with_name('launch_capture_bootstrap.py').resolve()),'--capture',payload],
                                stdout=worker_log,stderr=subprocess.STDOUT,start_new_session=True,
                                env=dict(os.environ,OBSERVATION_OWNER_PID=str(os.getpid())))
                            worker_identity.update(status='spawned',pid=worker.pid,group=worker.pid,spawn_returned=time.time(),spawn_returned_monotonic_ns=time.monotonic_ns())
                            try: write(directory/'observer-parent.json',worker_identity)
                            except OSError as exc:error('spawn-receipt',exc)
                            observation='worker-started'
                        except OSError as exc:
                            error('worker-start',exc)
                            observation='inconclusive'
            # Keep the xcode child unreaped until all sampling has stopped. A dead
            # unreaped child cannot have its PID reassigned to an unrelated process.
            while worker is not None:
                expire_worker()
                if worker is not None: time.sleep(0.025)
    finally:
        try:
            if worker is not None: worker_termination=stop_worker(worker)
        except (OSError,subprocess.SubprocessError) as exc:
            error('observer-final-cleanup',exc)
        if worker_log is not None:
            try: worker_log.close()
            except OSError as exc:error('worker-log-close',exc)
        if raw is not None:
            try: raw.close()
            except OSError as exc:error('raw-close',exc)
        for sig,handler in previous.items():signal.signal(sig,handler)
    # No diagnostic write precedes reaping the selected child at this point.
    code=process.wait()
    try: process.stdout.close()
    except OSError as exc:error('stream-close',exc)
    report=dict(schema=SCHEMA,bytes=total,sha256=digest.hexdigest(),long_lines=trigger.long_lines,
        downstream_broken=broken,first_trigger_only=True,errors=errors,observer=observation,
        selected_child_exit=code,worker_identity=worker_identity,worker_termination=worker_termination,perturbation='Additional pipe forwarding and one scoped host sample')
    try:
        stderr=directory/'observer-stderr.log'
        if stderr.exists():
            report['worker_stderr']={'path':str(stderr),'bytes':stderr.stat().st_size}
            with stderr.open('rb') as evidence: report['worker_stderr']['excerpt']=evidence.read(4096).decode('utf-8','replace')
        bootstrap=directory/'observer-bootstrap.json'
        report['bootstrap']=json.loads(bootstrap.read_text()) if bootstrap.exists() else {'status':'not-observed'}
        final=directory/'host-observation.json'
        value=json.loads(final.read_text()) if final.exists() else {}
        report['worker_final_receipt']='present' if 'finished' in value else 'missing-or-incomplete'
    except (OSError,ValueError) as exc:error('worker-evidence-read',exc)
    try: write(directory/'stdout-receipt.json',report)
    except OSError as exc:error('receipt-write',exc)
    if trigger.fired and not (directory/'host-observation.json').exists():
        try: write(directory/'host-observation.json',dict(schema=SCHEMA,status='inconclusive',error='Observer terminated or failed before receipt',pid=process.pid,identity=launch))
        except OSError as exc:error('observer-timeout-receipt',exc)
    if not trigger.fired:
        try: write(directory/'host-observation.json',dict(schema=SCHEMA,status='inconclusive',error='Exact launch trigger not observed',pid=process.pid,identity=launch))
        except OSError as exc:error('missing-trigger-receipt',exc)
    return code,report


if __name__=='__main__':
    from launch_capture_bootstrap import main
    if len(sys.argv)!=3 or sys.argv[1]!='--capture':raise SystemExit(2)
    raise SystemExit(main(json.loads(sys.argv[2])))

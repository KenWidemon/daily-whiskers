"""Record failures and bound process groups before the job's evidence reserve."""
import json
import math
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time


def write_record(path, record):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(record, indent=2))
    temporary.replace(path)


def initialize_budget(seconds, directory=Path('build')):
    if not math.isfinite(seconds) or seconds <= 0:
        raise ValueError('Execution budget must be positive and finite')
    directory.mkdir(parents=True, exist_ok=True)
    start = time.time()
    deadline = start + seconds
    write_record(directory / 'job-budget.json', {
        'started': start, 'execution_seconds': seconds, 'deadline': deadline,
        'source_sha': os.getenv('SOURCE_SHA'), 'run_id': os.getenv('GITHUB_RUN_ID'),
        'run_attempt': os.getenv('GITHUB_RUN_ATTEMPT'), 'job': os.getenv('GITHUB_JOB'),
        'shard': os.getenv('CI_SHARD_ID'),
    })
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        output.write(f'CI_EXECUTION_DEADLINE={deadline}\n')


def signal_group(process, signum):
    try:
        os.killpg(process.pid, signum)
        return True
    except ProcessLookupError:
        return False


def run(stage, command, directory=Path('build'), *, deadline=None, grace_seconds=60):
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f'{stage}-status.json'
    start = time.time()
    monotonic_start = time.monotonic()
    record = {'stage': stage, 'status': 'running', 'started': start,
              'source_sha': os.getenv('SOURCE_SHA'), 'tested_sha': os.getenv('TESTED_SHA'),
              'run_id': os.getenv('GITHUB_RUN_ID'), 'run_attempt': os.getenv('GITHUB_RUN_ATTEMPT'),
              'job': os.getenv('GITHUB_JOB'), 'shard': os.getenv('CI_SHARD_ID')}
    if deadline is not None:
        if not math.isfinite(deadline):
            raise ValueError('Execution deadline must be finite')
        record['deadline'] = deadline
    write_record(path, record)
    interrupted = []
    previous_handlers = {}
    process = None
    code = 127
    reason = None

    def terminate(signum):
        try:
            return signal_group(process, signum)
        except OSError as error:
            # A denied cleanup signal is not proof the descendants stopped.
            record.setdefault('cleanup_errors', []).append({
                'signal': signal.Signals(signum).name, 'error': type(error).__name__,
                'errno': error.errno})
            return False

    # Translate the cross-step wall-clock deadline once; subsequent watchdog
    # checks use a monotonic clock so clock corrections cannot extend this stage.
    stop_at = None if deadline is None else monotonic_start + max(0, deadline - start)
    try:
        for signum in (signal.SIGTERM, signal.SIGINT):
            previous_handlers[signum] = signal.signal(signum, lambda sig, frame: interrupted.append(sig))
        with (directory / f'{stage}.log').open('wb') as log:
            if stop_at is not None and time.monotonic() >= stop_at:
                reason = 'timed_out'
                record['error'] = 'Execution budget exhausted before stage; command not started'
            else:
                process = subprocess.Popen(command, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT, start_new_session=True)
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    shutdown_at = None
                    while True:
                        now = time.monotonic()
                        if reason is None and interrupted:
                            reason = 'interrupted'
                            record['signal'] = interrupted[0]
                        if reason is None and stop_at is not None and now >= stop_at:
                            reason = 'timed_out'
                        if reason is not None and shutdown_at is None:
                            shutdown_at = now + grace_seconds
                            record.update(status=reason, termination_signal='SIGTERM')
                            write_record(path, record)
                            # xcodebuild gets time to finalize the result bundle.
                            terminate(signal.SIGTERM)
                        if shutdown_at is not None and now >= shutdown_at:
                            record['forced_kill'] = terminate(signal.SIGKILL)
                            break
                        for key, _ in selector.select(timeout=0.05):
                            chunk = os.read(key.fileobj.fileno(), 65536)
                            if chunk:
                                log.write(chunk)
                                log.flush()
                                # Retained file is authoritative if CI's output pipe closes.
                                try:
                                    sys.stdout.write(chunk.decode('utf-8', errors='replace'))
                                    sys.stdout.flush()
                                except BrokenPipeError:
                                    pass
                            else:
                                selector.unregister(key.fileobj)
                        if process.poll() is not None and not selector.get_map():
                            break
                process.stdout.close()
                try:
                    code = process.wait(timeout=5)
                    record['command_exit_code'] = code
                except subprocess.TimeoutExpired:
                    record['error'] = 'Process did not reap after bounded shutdown'
                    code = 137
                # A child can survive after the parent closes its output. Attempt
                # descendant cleanup; denied signals remain explicit uncertainty.
                if reason is not None:
                    if terminate(signal.SIGKILL):
                        record['forced_kill'] = True
    except OSError as error:
        record['error'] = type(error).__name__
        if process is not None:
            terminate(signal.SIGKILL)
            try:
                record['command_exit_code'] = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                record['cleanup_reap_error'] = 'Process did not reap after bounded shutdown'
        code = 127
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
    if reason == 'timed_out':
        code = 124
    elif reason == 'interrupted':
        code = 128 + interrupted[0]
    elif code < 0:
        code = 128 - code
    record.update(status=reason or ('success' if code == 0 else 'failure'), exit_code=code,
                  duration_seconds=round(time.monotonic() - monotonic_start, 2))
    write_record(path, record)
    return code


if __name__ == '__main__':
    try:
        if sys.argv[1] == 'init-budget':
            initialize_budget(float(sys.argv[2]))
            sys.exit(0)
        raw = os.getenv('CI_EXECUTION_DEADLINE')
        if os.getenv('GITHUB_ACTIONS') == 'true' and not raw:
            raise ValueError('Hosted stages require an initialized execution deadline')
        sys.exit(run(sys.argv[1], sys.argv[2:], deadline=float(raw) if raw else None))
    except (ValueError, IndexError) as error:
        print(f'::error::{error}', file=sys.stderr)
        sys.exit(2)

"""Small POSIX command supervisor for the app-free hosted probe only.

The controller exists before fork/setsid/exec. The child waits for permission,
checks the absolute deadline again, then execs without a blocking Popen path.
OS scheduling and filesystem stalls are not bounded by a Python watchdog.
"""
import json
import os
from pathlib import Path
import selectors
import signal
import time

OUTPUT_LIMIT = 256 * 1024
COMMAND_LIMIT = 32


def write(path, data):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(path)


class CommandFailure(RuntimeError):
    pass


def group_absent(pid):
    try:
        os.killpg(pid, 0)
        return False
    except ProcessLookupError:
        return True
    except PermissionError:
        return None


def signal_group(pid, number, record):
    try:
        os.killpg(pid, number)
    except ProcessLookupError:
        pass
    except OSError as error:
        record.setdefault('signal_errors', []).append({'signal': number, 'errno': error.errno})


def child_exec(argv, output_fd, event_fd, gate_fd, deadline):
    """Only this new child may establish and use this task-owned session."""
    try:
        signal.signal(signal.SIGINT, signal.SIG_DFL)
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        os.setsid()
        os.dup2(output_fd, 1)
        os.dup2(output_fd, 2)
        os.write(event_fd, (json.dumps({'event': 'ready', 'pid': os.getpid(),
                                      'pgid': os.getpgrp()}) + '\n').encode())
        if os.read(gate_fd, 1) != b'G' or time.monotonic() >= deadline:
            os._exit(125)
        os.write(event_fd, (json.dumps({'event': 'exec', 'wall': time.time(),
                                      'monotonic': time.monotonic()}) + '\n').encode())
        # This is the last user-space check before exec. A descheduled kernel or
        # stalled exec cannot be represented as a hard real-time guarantee.
        if time.monotonic() >= deadline:
            os._exit(125)
        os.execvp(argv[0], argv)
    except BaseException as error:
        os.write(2, f'Command could not exec: {type(error).__name__}\n'.encode())
        os._exit(127)


class Supervisor:
    def __init__(self, directory, phase, seconds, shutdown_seconds, *, clock=time.monotonic):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.phase = phase
        self.clock = clock
        self.started = clock()
        self.deadline = self.started + seconds
        self.hard_deadline = self.deadline + shutdown_seconds
        self.shutdown_remaining = shutdown_seconds
        self.commands = []
        self.interrupted = None
        self.failed = False
        self.handlers = {}
        write(self.directory / f'{phase}-budget.json', {
            'wall_start': time.time(), 'monotonic_start': self.started,
            'execution_deadline': self.deadline, 'shutdown_deadline': self.hard_deadline,
            'execution_seconds': seconds, 'shutdown_seconds': shutdown_seconds})

    def __enter__(self):
        for number in (signal.SIGINT, signal.SIGTERM):
            self.handlers[number] = signal.signal(number, self.interrupt)
        return self

    def __exit__(self, *_):
        for number, handler in self.handlers.items():
            signal.signal(number, handler)

    def interrupt(self, number, _frame):
        self.interrupted = number

    def run(self, name, argv, timeout=10, *, evidence=False, absolute_deadline=None):
        if not argv or not all(isinstance(s, str) and s for s in argv):
            raise ValueError('A nonempty exact argv is required')
        if not 0 < timeout <= 300 or len(self.commands) >= COMMAND_LIMIT:
            raise CommandFailure('Invalid command limit')
        start = self.clock()
        deadline = min(self.deadline, start + timeout, absolute_deadline if absolute_deadline is not None else self.deadline)
        record = {'name': name, 'argv': argv, 'wall_start': time.time(),
                  'monotonic_start': start, 'timeout_seconds': timeout,
                  'operation_deadline': deadline, 'shared_deadline': self.deadline,
                  'pid': None, 'pgid': None, 'launch_authorized': False,
                  'exec_attempt_observed': False, 'exit_code': None, 'reaped': False,
                  'group_absent': None, 'output_bytes': 0, 'output_truncated': False,
                  'status': 'pending', 'controller_pid': os.getpid()}
        self.commands.append(record)
        prefix = f'{self.phase}-{len(self.commands):02d}-{name}'
        path = self.directory / f'{prefix}.json'
        write(path, record)
        if start >= deadline or self.interrupted or (self.failed and not evidence) or any(
                r['status'] not in ('pending', 'not_started') and
                (not r['reaped'] or r['group_absent'] is not True) for r in self.commands[:-1]):
            record['status'] = 'not_started'
            self.finish(record, path)
            raise CommandFailure(f'{name}: not started (deadline/cancellation/prior failure)')
        (self.directory / f'{prefix}.log').touch()
        output = bytearray()
        pid = None
        verified = False
        reaped = False
        stop_at = None
        kill_at = None
        stopped_at = None
        reason = None
        fds = []
        try:
            out_read, out_write = os.pipe()
            event_read, event_write = os.pipe()
            gate_read, gate_write = os.pipe()
            fds = [out_read, out_write, event_read, event_write, gate_read, gate_write]
            # Persist intent before fork; no external tool precedes this controller.
            record['status'] = 'starting'
            write(path, record)
            pid = os.fork()
            if pid == 0:
                for fd in (out_read, event_read, gate_write):
                    os.close(fd)
                child_exec(argv, out_write, event_write, gate_read, deadline)
                os._exit(127)
            record['pid'] = pid
            for fd in (out_write, event_write, gate_read):
                os.close(fd)
                fds.remove(fd)
            os.set_blocking(out_read, False)
            os.set_blocking(event_read, False)
            events = b''
            last_flush = self.clock()
            with (self.directory / f'{prefix}.log').open('wb') as log, selectors.DefaultSelector() as selector:
                selector.register(out_read, selectors.EVENT_READ, 'output')
                selector.register(event_read, selectors.EVENT_READ, 'events')
                while True:
                    now = self.clock()
                    if reason is None and self.interrupted:
                        reason = 'interrupted'
                    if reason is None and now >= deadline:
                        reason = 'timed_out'
                    if reason is not None and stop_at is None:
                        stopped_at = now
                        stop_at = min(self.hard_deadline, now + self.shutdown_remaining)
                        kill_at = min(stop_at, now + min(1, self.shutdown_remaining / 2))
                        record['status'] = reason
                        record['timeout_observed_wall'] = time.time()
                        record['timeout_observed_monotonic'] = now
                        write(path, record)
                        if verified:
                            signal_group(pid, signal.SIGTERM, record)
                        else:
                            # An unacknowledged child has not been allowed to exec.
                            try:
                                os.kill(pid, signal.SIGTERM)
                            except OSError as error:
                                record.setdefault('signal_errors', []).append({'signal': signal.SIGTERM, 'errno': error.errno})
                    if stop_at is not None and now >= kill_at:
                        if verified:
                            signal_group(pid, signal.SIGKILL, record)
                        elif not reaped:
                            try:
                                os.kill(pid, signal.SIGKILL)
                            except OSError as error:
                                record.setdefault('signal_errors', []).append({'signal': signal.SIGKILL, 'errno': error.errno})
                        kill_at = float('inf')
                    if not reaped:
                        waited, status = os.waitpid(pid, os.WNOHANG)
                        if waited:
                            reaped = True
                            record['reaped'] = True
                            record['exit_code'] = os.waitstatus_to_exitcode(status)
                    absent = group_absent(pid) if verified else (True if reaped else None)
                    record['group_absent'] = absent
                    if reaped and not selector.get_map() and absent is True:
                        break
                    if reaped and reason is None and absent is not True:
                        reason = 'descendants_unresolved'
                    if stop_at is not None and now >= stop_at:
                        break
                    for key, _ in selector.select(timeout=min(.05, max(0, (stop_at or deadline) - now))):
                        chunk = os.read(key.fd, 65536)
                        if not chunk:
                            selector.unregister(key.fd)
                        elif key.data == 'output':
                            remaining = max(0, OUTPUT_LIMIT - len(output))
                            retained = chunk[:remaining]
                            output.extend(retained)
                            log.write(retained)
                            record['output_bytes'] += len(chunk)
                            if len(chunk) > remaining:
                                record['output_truncated'] = True
                                reason = reason or 'output_limit'
                        else:
                            events += chunk
                            if len(events) > 4096:
                                reason = reason or 'invalid_handshake'
                                continue
                            while b'\n' in events:
                                line, events = events.split(b'\n', 1)
                                message = json.loads(line)
                                if message['event'] == 'ready':
                                    if message['pid'] != pid or message['pgid'] != pid or os.getpgid(pid) != pid:
                                        reason = reason or 'invalid_handshake'
                                        continue
                                    verified = True
                                    record['pgid'] = pid
                                    if self.clock() < deadline and not self.interrupted and reason is None:
                                        record['launch_authorized'] = True
                                        write(path, record)
                                        # The child also checks the deadline after receiving this.
                                        os.write(gate_write, b'G')
                                elif message['event'] == 'exec':
                                    record.update(exec_attempt_observed=True, exec_wall=message['wall'],
                                                  exec_monotonic=message['monotonic'])
                                    write(path, record)
                    if self.clock() - last_flush >= 1:
                        log.flush()
                        last_flush = self.clock()
                log.flush()
            if reason is None and record['exit_code'] == 0 and record['exec_attempt_observed'] and reaped and record['group_absent'] is True:
                record['status'] = 'success'
            else:
                record['status'] = reason or 'failure'
        except (OSError, ValueError, KeyError) as error:
            record.update(status='supervisor_error', error=f'{type(error).__name__}: {error}')
            # Do not invent reaping after an unexpected controller error.
            if pid and verified:
                signal_group(pid, signal.SIGKILL, record)
            elif pid:
                try:
                    os.kill(pid, signal.SIGKILL)
                except OSError:
                    pass
            if pid:
                # Exceptional paths still get only the already reserved time.
                # WNOHANG and independent group readback never invent a reap.
                exceptional_start = self.clock()
                exceptional_end = min(self.hard_deadline, exceptional_start + self.shutdown_remaining,
                                      stop_at if stop_at is not None else self.hard_deadline)
                while self.clock() < exceptional_end:
                    if not record['reaped']:
                        try:
                            waited, status = os.waitpid(pid, os.WNOHANG)
                            if waited:
                                record.update(reaped=True, exit_code=os.waitstatus_to_exitcode(status))
                        except OSError as reap_error:
                            record['reap_error'] = type(reap_error).__name__
                            break
                    record['group_absent'] = group_absent(pid) if verified else (True if record['reaped'] else None)
                    if record['reaped'] and record['group_absent'] is True:
                        break
                    time.sleep(min(.05, max(0, exceptional_end - self.clock())))
                if stopped_at is None:
                    self.shutdown_remaining = max(0, self.shutdown_remaining - (self.clock() - exceptional_start))
        finally:
            if stopped_at is not None:
                self.shutdown_remaining = max(0, self.shutdown_remaining - (self.clock() - stopped_at))
            for fd in fds:
                try:
                    os.close(fd)
                except OSError:
                    pass
            self.finish(record, path)
        if record['status'] != 'success':
            self.failed = True
            raise CommandFailure(f"{name}: {record['status']}; reaped={record['reaped']}; group_absent={record['group_absent']}")
        return bytes(output).decode('utf-8', errors='replace').strip()

    def finish(self, record, path):
        record.update(wall_end=time.time(), monotonic_end=self.clock())
        record['duration_seconds'] = record['monotonic_end'] - record['monotonic_start']
        write(path, record)

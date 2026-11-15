#!/usr/bin/env python3
"""Local-only bounded prefix witness. Not invoked by the hosted workflow.

Proposed command (interface must be locally verified before execution):
  xcrun simctl get_app_container <verified-owned-UDID> com.example.kenwidemon.dailywhiskers data
No lookup is performed by offline fixtures. No complete-tail/negative inference.
"""
import json
import math
import os
from pathlib import Path
import stat
import uuid

import reminder_boundary as b

BUNDLE = 'com.example.kenwidemon.dailywhiskers'
CAP = 64 * 1024
# Preserve 270 seconds for cleanup/finalization plus 75 for child settlement.
EXPORT_RESERVE = 345
FIELDS = set('schema run pid seq tick stage id command requested enabled authorization queued hasCoverage hasMessage storageBlocked cleanupPending busy loaded operations'.split())
BOOLS = set('enabled hasCoverage hasMessage storageBlocked cleanupPending busy loaded'.split())
TOP = set('witnessSchema kind run pid eventCount lastSequence replacementAttempts overflow measuredWrites writeNanoseconds events'.split())
LIMITATIONS = ['A retained prefix never proves noninvocation or completeness, even without overflow.',
               'A failed later replacement can leave an earlier valid prefix; the lost tail is unknowable.',
               'Write counters describe prior successful writes, not the final write duration or a latency guarantee.',
               'No cross-clock subtraction, product acceptance, or raw-test-outcome override.',
               'At bindingSetter, operations=-1 means unsampled, not an operation count; id=0 means no send-command identity yet. Model/status fields are sampled by the emitter.']
INTERPRETATION = {
    'bindingSetter': {
        'operations_minus_one': 'unsampled; not an operation count',
        'id_zero': 'no send-command identity yet',
        'sampled_model_fields': ['enabled','authorization','queued','hasCoverage','hasMessage',
                                 'storageBlocked','cleanupPending','busy','loaded']
    }
}


def integer(v, low=0, high=2**63-1):
    return type(v) is int and low <= v <= high


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        b.require(key not in result, 'Duplicate JSON key')
        result[key] = value
    return result


def classify(raw, identity):
    result = {'valid': False, 'kind': 'prefix', 'negative_marker_inference_qualified': False,
              'errors': [], 'records': [], 'limitations': LIMITATIONS, 'interpretation': INTERPRETATION}
    try:
        b.require(len(raw) <= CAP, 'Snapshot exceeds 64 KiB')
        doc = json.loads(raw, object_pairs_hook=unique_object)
        b.require(type(doc) is dict and set(doc) == TOP, 'Snapshot fields/schema')
        b.require(type(doc['witnessSchema']) is int and doc['witnessSchema'] == 1 and doc['kind'] == 'prefix', 'Snapshot schema/kind')
        b.require(str(uuid.UUID(doc['run'])).upper() == doc['run'], 'Snapshot UUID')
        b.require(integer(doc['pid'], 1) and {'run': doc['run'], 'pid': doc['pid']} == identity, 'Snapshot/Session identity mismatch')
        b.require(type(doc['overflow']) is bool and type(doc['events']) is list, 'Snapshot types')
        n = len(doc['events'])
        b.require((1 <= n <= 64 or n == 0 and doc['overflow']) and integer(doc['eventCount'], 0, 64) and doc['eventCount'] == n and integer(doc['lastSequence'], 0, 64) and doc['lastSequence'] == n, 'Snapshot event counters')
        attempts = n + int(doc['overflow'])
        b.require(integer(doc['replacementAttempts'], 1, 65) and doc['replacementAttempts'] == attempts and integer(doc['measuredWrites']) and doc['measuredWrites'] == attempts-1 and integer(doc['writeNanoseconds'], 0, 2**64-1), 'Snapshot write counters')
        b.require(doc['measuredWrites'] != 0 or doc['writeNanoseconds'] == 0, 'Timing without measured writes')
        commands, ticks, setters = {}, [], []
        for seq, r in enumerate(doc['events'], 1):
            b.require(type(r) is dict and set(r) == FIELDS, 'Event fields')
            b.require(all(type(r[k]) is bool for k in BOOLS), 'Event boolean')
            b.require(all(integer(r[k]) for k in ('schema','pid','seq','id','queued')), 'Event integer')
            b.require(integer(r['operations'], -1 if r['stage'] == 'bindingSetter' else 0), 'Event operations')
            b.require(type(r['requested']) is int and r['requested'] in (-1,0,1), 'Requested value')
            b.require(type(r['tick']) in (int,float) and math.isfinite(r['tick']) and r['tick'] >= 0, 'Event tick')
            b.require(r['schema'] == 1 and r['seq'] == seq and r['pid'] == doc['pid'] and r['run'] == doc['run'], 'Event identity/sequence')
            b.require(r['authorization'] in ('notDetermined','denied','authorized','quiet'), 'Event authorization')
            b.require(r['stage'] in ('ready','bindingSetter','sendEntry','statusPublished','sendComplete') and r['command'] in ('none','enable','refresh','time'), 'Event stage/command')
            b.require((r['requested'] in (0,1)) if r['command'] == 'enable' else r['requested'] == -1, 'Command requested mismatch')
            b.require((seq == 1) == (r['stage'] == 'ready'), 'Ready prefix')
            if r['stage'] in ('ready','bindingSetter'):
                b.require(r['id'] == 0 and r['command'] == ('none' if r['stage'] == 'ready' else 'enable'), 'Noncommand event')
                if r['stage'] == 'bindingSetter' and r['requested'] == 1:
                    setters.append(r)
            else:
                b.require(r['id'] > 0 and r['command'] != 'none', 'Command event')
                commands.setdefault(r['id'], []).append(r)
            ticks.append(r['tick'])
        b.require(ticks == sorted(ticks), 'Nonmonotonic event ticks')
        entries = [r['id'] for r in doc['events'] if r['stage'] == 'sendEntry']
        b.require(entries == list(range(1,len(entries)+1)), 'Command entry order')
        for group in commands.values():
            b.require([r['stage'] for r in group] in (['sendEntry'], ['sendEntry','statusPublished'], ['sendEntry','statusPublished','sendComplete']) and len({(r['command'],r['requested']) for r in group}) == 1, 'Command stage relationship')
        enable = [g for g in commands.values() if g[0]['command'] == 'enable' and g[0]['requested'] == 1]
        b.require(len(setters) <= 1 and len(enable) <= 1, 'Multiple enable attempts')
        result.update(valid=True, records=doc['events'], commands=commands, overflow=doc['overflow'], counters={k:doc[k] for k in ('eventCount','lastSequence','replacementAttempts','measuredWrites','writeNanoseconds')},
                      observed={'enableSetter':bool(setters), 'enableEntry':bool(enable), 'enableComplete':bool(enable and enable[0][-1]['stage'] == 'sendComplete')})
    except (b.Invalid, ValueError, TypeError, KeyError, AttributeError, OverflowError) as exc:
        result['errors'].append(str(exc))
    return result


def read_exact(container, run, budget):
    """Walk using no-follow directory descriptors; never enumerate or export a tree."""
    b.require(str(uuid.UUID(run)).upper() == run, 'Invalid exact snapshot UUID')
    root = Path(container)
    b.require(root.is_absolute() and '..' not in root.parts and str(root) == container and root != Path('/'), 'Invalid container path')
    parts = (*root.parts[1:], 'Library', 'Application Support', 'ReminderEnableProbe', run+'.json')
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in parts[:-1]:
            b.require(budget.remaining(True) > EXPORT_RESERVE, 'Snapshot finalization deadline')
            new = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = new
        file_fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
        try:
            before = os.fstat(file_fd)
            b.require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1 and before.st_size <= CAP, 'Snapshot is not a capped regular file')
            b.require(budget.remaining(True) > EXPORT_RESERVE, 'Snapshot finalization deadline')
            raw = os.read(file_fd, CAP+1)
            after = os.fstat(file_fd)
            b.require(len(raw) <= CAP and len(raw) == before.st_size and (before.st_size,before.st_mtime_ns,before.st_ctime_ns) == (after.st_size,after.st_mtime_ns,after.st_ctime_ns), 'Snapshot changed during read')
            b.require(budget.remaining(True) > EXPORT_RESERVE, 'Snapshot post-read deadline')
            return raw
        finally:
            os.close(file_fd)
    finally:
        os.close(fd)


def finalize_local(c, collector, uid, name, before, raw_test_exit, source_valid=False):
    """Single-use local finalizer. Export failures cannot prevent safe cleanup.

    Caller supplies the existing Collector and original Commands/Budget. Never
    instantiate a fresh budget here. raw_test_exit is returned without alteration.
    No creation reconciliation or fallback ownership/identity is attempted.
    """
    receipt = {'raw_test_exit':raw_test_exit, 'export':{'exported':False}, 'cleanup':{'verified':False}, 'collector':None}
    export = receipt['export']
    try:
        c.settle(c.budget.started+2700)
        b.require(c.settled, 'Unsettled owned group; no snapshot or cleanup')
        current = b.flat(json.loads(c.run('local-ownership', ['xcrun','simctl','list','devices','-j'],45,final=True)))
        b.require(before is not None and b.owns(uid,name,before,current), 'Local ownership uncertain')
        prior_reserve = getattr(collector, 'final_reserve', 75)
        try:
            b.require(c.budget.remaining(True) > EXPORT_RESERVE, 'Snapshot export reserve exhausted')
            collector.final_reserve = EXPORT_RESERVE
            identity = collector.launch_identity()
            export['identity'] = identity
            argv = ['xcrun','simctl','get_app_container',uid,BUNDLE,'data']
            export['container_command'] = argv
            container = c.run('local-snapshot-container',argv,45,final=True,reserve=EXPORT_RESERVE).decode('utf-8').rstrip('\n')
            b.require('\n' not in container and '\r' not in container, 'Ambiguous container output')
            export['container'] = container
            raw = read_exact(container, identity['run'], c.budget)
            target = collector.output/'snapshot-prefix.raw.json'
            b.require(c.budget.remaining(True) > EXPORT_RESERVE, 'Snapshot pre-artifact deadline')
            with target.open('xb') as handle:
                handle.write(raw)
            export.update(exported=True, bytes=len(raw), sha256=b.sha(raw), relative_path='Library/Application Support/ReminderEnableProbe/'+identity['run']+'.json')
            export['classification'] = classify(raw,identity)
        except (Exception, KeyboardInterrupt) as exc:
            export['error'] = type(exc).__name__+': '+str(exc)
        finally:
            collector.final_reserve = prior_reserve
        try:
            b.save(collector.output/'snapshot-export-receipt.json',export)
        except OSError as exc:
            export['receipt_error'] = str(exc)
        # The command wrapper checks settlement/deadline again for each action.
        b.require(c.settled, 'Unsettled snapshot group; no simulator cleanup')
        if current[uid]['state'] != 'Shutdown':
            c.run('local-cleanup-shutdown',['xcrun','simctl','shutdown',uid],60,final=True)
        c.run('local-cleanup-delete',['xcrun','simctl','delete',uid],60,final=True)
        after = b.flat(json.loads(c.run('local-cleanup-readback',['xcrun','simctl','list','devices','-j'],45,final=True)))
        receipt['cleanup'].update(verified=uid not in after and b.stable(after) == b.stable(before), owned_deleted=uid not in after, preexisting_stable=b.stable(after) == b.stable(before))
    except (Exception, KeyboardInterrupt) as exc:
        receipt['cleanup']['error'] = type(exc).__name__+': '+str(exc)
        if 'error' not in export and not export['exported']:
            export['error'] = 'Export not attempted: '+str(exc)
    if c.settled:
        try:
            receipt['collector'] = collector.collect(uid,source_valid)
        except (Exception, KeyboardInterrupt) as exc:
            receipt['collector'] = {'capture_valid':False, 'capture_errors':[type(exc).__name__+': '+str(exc)]}
    b.save(collector.output/'snapshot-export-receipt.json',export)
    b.save(collector.output/'local-finalization.json',receipt)
    return receipt

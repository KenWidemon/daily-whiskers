#!/usr/bin/env python3
"""Host-only exact-source writer fixtures. Never invokes iOS, Xcodebuild or simctl."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

REPO = Path(__file__).resolve().parents[1]
SOURCE = REPO / 'DailyWhiskers/Reminders/ReminderProbeSnapshot.swift'
GUARD = '#if DEBUG && CI_SMOKE_TESTING && DW_REMINDER_ENABLE_PROBE && targetEnvironment(simulator)\n'

def run(output):
    output.mkdir(exist_ok=False)
    source = SOURCE.read_text()
    assert source.startswith(GUARD) and source.endswith('#endif\n')
    # Strip only the single enclosing compile guard. Every byte of the executed
    # writer body is taken directly from the checked-in app source, not a model.
    body = source[len(GUARD):-len('#endif\n')]
    extracted = output/'ExactWriter.swift'
    extracted.write_text(body)
    harness = REPO/'ci/reminder_snapshot_writer_harness.swift'
    commands = []
    def command(name, argv, env=None):
        result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        (output/(name+'.stdout')).write_bytes(result.stdout)
        (output/(name+'.stderr')).write_bytes(result.stderr)
        commands.append({'name':name,'argv':argv,'exit':result.returncode})
        (output/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
        result.check_returncode()
        return result.stdout
    command('swift-version',['/usr/bin/swiftc','--version'])
    binary=output/'writer-fixtures'
    command('compile-writer',['/usr/bin/swiftc','-parse-as-library','-o',str(binary),str(extracted),str(harness)])
    command('run-writer',[str(binary),str(output/'fixtures')])
    # In normal Debug, Release, and non-simulator probe builds the source must
    # compile to an object containing no writer symbols. This is not an iOS build.
    for name, flags in [('release',[]),('debug',['-DDEBUG']),('smoke',['-DDEBUG','-DCI_SMOKE_TESTING']),
                        ('host-probe',['-DDEBUG','-DCI_SMOKE_TESTING','-DDW_REMINDER_ENABLE_PROBE'])]:
        obj=output/(name+'.o')
        command('exclude-'+name,['/usr/bin/swiftc','-parse-as-library',*flags,'-c',str(SOURCE),'-o',str(obj)])
        symbols=command('symbols-'+name,['/usr/bin/nm',str(obj)])
        assert b'ReminderProbe' not in symbols
    smoke=(REPO/'DailyWhiskers/Reminders/ReminderSmoke.swift').read_text()
    probe=smoke[smoke.index('@MainActor\nenum ReminderEnableProbe'):]
    assert probe.endswith('#endif\n#endif\n')
    probe=probe[:-len('#endif\n#endif\n')]
    # Select only the simulator branch for a host-only fixture. No app models,
    # SwiftUI, real application support path or simulator process is involved.
    selected=[]
    include=True
    for line in probe.splitlines(keepends=True):
        if line.strip()=='#if targetEnvironment(simulator)': include=True
        elif line.strip()=='#else': include=False
        elif line.strip()=='#endif': include=True
        elif include: selected.append(line)
    probe=''.join(selected)
    logger='Logger(subsystem: "DailyWhiskers", category: "ReminderEnableProbe")'
    destination='FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first'
    assert probe.count(logger)==1 and probe.count(destination)==1
    probe=probe.replace(logger,'Logger.disabled').replace(destination,'Optional(harnessSupport)')
    stubs='''import Foundation
import os
let harnessSupport = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
enum ReminderCommand { case refresh, enable(Bool), time(Int) }
struct FixtureAuthorization { let rawValue = "notDetermined" }
struct FixtureStatus {
    var enabled = false
    let authorization = FixtureAuthorization()
    var queued = 0
    var coverageEnd: Int? = nil
    var message: String? = nil
    var storageBlocked = false
    var cleanupPending = false
}
@MainActor final class ReminderModel {
    var status = FixtureStatus()
    var busy = false
    var loaded = false
}
@MainActor enum ReminderSmoke {
    static var controlsEnabled: Bool { ProcessInfo.processInfo.environment["FIXTURE_CONTROLS"] == "1" }
}
'''
    emitter=output/'ExactProbeWithOfflineSeams.swift'
    emitter.write_text(stubs+probe+'''
@main struct DisabledLoggerFixture {
    @MainActor static func main() throws {
        let model = ReminderModel()
        ReminderEnableProbe.record(.ready, model: model, operations: 0)
        model.status.enabled = true
        model.status.queued = 3
        model.status.coverageEnd = 123
        model.status.message = "fixture content must not be recorded"
        model.status.storageBlocked = true
        model.status.cleanupPending = true
        model.busy = true
        model.loaded = true
        ReminderEnableProbe.record(.bindingSetter, command: .enable(true), model: model)
        let id = ReminderEnableProbe.begin(.enable(true), model: model, operations: 0)
        model.status.enabled = true
        ReminderEnableProbe.record(.statusPublished, id: id, command: .enable(true), model: model, operations: 1)
        ReminderEnableProbe.record(.sendComplete, id: id, command: .enable(true), model: model, operations: 0)
    }
}
''')
    emitterBinary=output/'disabled-logger-fixture'
    command('compile-disabled-logger',['/usr/bin/swiftc','-parse-as-library','-o',str(emitterBinary),str(extracted),str(emitter)])
    runid='12345678-1234-4234-8234-123456789ABC'
    integration=[]
    for name, fixture_id, controls, flags, expected in [
        ('disabled-logger',runid,'1',['--ci-smoke-reminder-enable-probe'],True),
        ('missing-probe-argument',runid,'1',[],False),
        ('invalid-run-id','not-a-uuid','1',['--ci-smoke-reminder-enable-probe'],False),
        ('missing-run-id',None,'1',['--ci-smoke-reminder-enable-probe'],False),
        ('disabled-controls',runid,'0',['--ci-smoke-reminder-enable-probe'],False)]:
        support=output/name
        environment=dict(os.environ,FIXTURE_CONTROLS=controls,OS_ACTIVITY_MODE='disable')
        environment.pop('DW_REMINDER_TEST_ID',None)
        if fixture_id is not None: environment['DW_REMINDER_TEST_ID']=fixture_id
        command('integration-'+name,[str(emitterBinary),str(support),*flags],environment)
        file=support/'ReminderEnableProbe'/ (runid+'.json')
        assert file.exists()==expected
        if expected:
            payload=json.loads(file.read_bytes())
            assert payload['eventCount']==5 and payload['kind']=='prefix'
            assert [e['stage'] for e in payload['events']]==['ready','bindingSetter','sendEntry','statusPublished','sendComplete']
            setter=payload['events'][1]
            assert setter['operations']==-1 and setter['id']==0 and setter['queued']==3
            assert all(setter[k] is True for k in ['enabled','hasCoverage','hasMessage','storageBlocked','cleanupPending','busy','loaded'])
            assert b'fixture content' not in file.read_bytes()
            assert payload['events'][0]['enabled'] is False
        else: assert not support.exists()
        integration.append(name)
    (output/'integration-results.json').write_text(json.dumps({'passed':integration,'passedCount':len(integration),
        'writerBodyUnchanged':True,'emitterFixtureSeams':['Selected simulator compilation branch',
            'Replaced logger initialization with Logger.disabled','Redirected support-directory URL to isolated fixture root',
            'Provided minimal model/command/control stubs instead of app or SwiftUI']},indent=2)+'\n')
    (output/'source-contract.json').write_text(json.dumps({'appSource':str(SOURCE),
        'sourceSha256':hashlib.sha256(source.encode()).hexdigest(),
        'exactBodySha256':hashlib.sha256(body.encode()).hexdigest(),
        'harnessSha256':hashlib.sha256(harness.read_bytes()).hexdigest(),
        'onlyWriterTransformation':'Removed one enclosing conditional-compilation guard for host fixture execution.',
        'notExecuted':['iOS app build','xcodebuild','simulator operations','UI test']},indent=2)+'\n')
    print((output/'fixtures/writer-results.json').read_text())

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    run(p.parse_args().output.resolve())

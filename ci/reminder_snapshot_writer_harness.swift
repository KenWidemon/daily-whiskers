import Foundation

private enum FixtureFailure: Error { case injected }
@MainActor
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "OfflineFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
struct WriterFixtures {
    @MainActor
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let run = "12345678-1234-4234-8234-123456789ABC"
        let pid: Int32 = 99
        var passed: [String] = []
        func event(_ seq: Int, stage: String = "ready", id: Int = 0,
                   command: String = "none", requested: Int = -1) -> ReminderProbeEvent {
            ReminderProbeEvent(schema: 1, run: run, pid: pid, seq: seq, tick: Double(seq),
                stage: stage, id: id, command: command, requested: requested, enabled: false,
                authorization: "notDetermined", queued: 0, hasCoverage: false,
                hasMessage: false, storageBlocked: false, cleanupPending: false,
                busy: false, loaded: false, operations: 0)
        }
        func directory(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }
        func data(_ name: String) throws -> Data {
            try Data(contentsOf: directory(name).appendingPathComponent(run + ".json"))
        }
        func object(_ bytes: Data) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        }
        func prefix(_ name: String) throws -> [String: Any] { try object(data(name)) }

        let writer = ReminderProbeSnapshotWriter(run: run, pid: pid, directory: directory("known"))
        let known = [event(1), event(2, stage: "sendEntry", id: 1, command: "refresh"),
            event(3, stage: "bindingSetter", command: "enable", requested: 1),
            event(4, stage: "sendEntry", id: 2, command: "enable", requested: 1),
            event(5, stage: "statusPublished", id: 1, command: "refresh"),
            event(6, stage: "sendComplete", id: 1, command: "refresh"),
            event(7, stage: "statusPublished", id: 2, command: "enable", requested: 1),
            event(8, stage: "sendComplete", id: 2, command: "enable", requested: 1)]
        for value in known { writer.append(value) }
        let snapshot = try prefix("known")
        try check(snapshot["eventCount"] as? Int == known.count, "known sequence count")
        try check((snapshot["events"] as? [[String: Any]])?.map { $0["seq"] as! Int } == Array(1...8), "same immutable events")
        try check(snapshot["kind"] as? String == "prefix", "never complete")
        try check(snapshot["measuredWrites"] as? Int == 7, "timing covers prior writes")
        try check(writer.successfulWrites == 8 && writer.totalWriteNanoseconds > 0, "actual overhead measured")
        passed.append("known sequence and refresh interleaving")

        let staleDirectory = directory("stale")
        try FileManager.default.createDirectory(at: staleDirectory, withIntermediateDirectories: true)
        let staleFile = staleDirectory.appendingPathComponent(run + ".json")
        let stale = Data("old run bytes must be preserved".utf8)
        try stale.write(to: staleFile)
        let staleWriter = ReminderProbeSnapshotWriter(run: run, pid: pid, directory: staleDirectory)
        staleWriter.append(event(1)); staleWriter.append(event(2))
        try check(staleWriter.stopped && staleWriter.attempts == 1, "stale file disables")
        let retainedStale = try Data(contentsOf: staleFile)
        try check(retainedStale == stale, "stale bytes unchanged")
        passed.append("pre-existing file preserved and no further writes")

        let blocked = directory("init-failure")
        try Data("not a directory".utf8).write(to: blocked)
        let failedInit = ReminderProbeSnapshotWriter(run: run, pid: pid, directory: blocked)
        failedInit.append(event(1)); failedInit.append(event(2))
        try check(failedInit.stopped && failedInit.attempts == 1 && failedInit.successfulWrites == 0, "initialization failure")
        passed.append("initialization failure is terminal")

        var calls = 0
        var retained: Data?
        let failedFinal = ReminderProbeSnapshotWriter(run: run, pid: pid, directory: directory("unused"), replace: { bytes in
            calls += 1
            if calls == 2 { throw FixtureFailure.injected }
            retained = bytes
        })
        failedFinal.append(event(1)); failedFinal.append(event(2)); failedFinal.append(event(3))
        let retainedPrefix = try object(retained!)
        try check(calls == 2 && failedFinal.stopped && retainedPrefix["eventCount"] as? Int == 1, "final failed write leaves earlier prefix")
        passed.append("final write failure preserves prefix without retries")

        var initialCalls = 0
        let failedFirst = ReminderProbeSnapshotWriter(run: run, pid: pid, directory: directory("unused"), replace: { _ in
            initialCalls += 1; throw FixtureFailure.injected
        })
        failedFirst.append(event(1)); failedFirst.append(event(2))
        try check(initialCalls == 1 && failedFirst.successfulWrites == 0, "first write no retry")
        passed.append("first write failure is terminal")

        let overflow = ReminderProbeSnapshotWriter(run: run, pid: pid, directory: directory("overflow"))
        for seq in 1...100 { overflow.append(event(seq, stage: seq == 1 ? "ready" : "sendEntry", id: seq == 1 ? 0 : seq - 1, command: seq == 1 ? "none" : "refresh")) }
        let overflowPrefix = try prefix("overflow")
        try check(overflow.stopped && overflow.attempts == 65 && overflow.successfulWrites == 65, "65-attempt ceiling")
        try check(overflowPrefix["eventCount"] as? Int == 64 && overflowPrefix["overflow"] as? Bool == true, "64-event prefix and overflow marker")
        let overflowBytes = try data("overflow")
        try check(overflowBytes.count <= 65536, "byte ceiling")
        passed.append("event overflow emits one bounded final prefix then stops")

        var encodes = 0
        var largeWrites = 0
        let tooLarge = ReminderProbeSnapshotWriter(run: run, pid: pid, directory: directory("unused"), replace: { _ in largeWrites += 1 }, encode: { _ in
            encodes += 1; return Data(repeating: 65, count: 65537)
        })
        tooLarge.append(event(1)); tooLarge.append(event(2))
        try check(tooLarge.stopped && tooLarge.attempts == 1 && encodes == 2 && largeWrites == 0, "never write oversized bytes")
        passed.append("oversized serialization stops without writing oversized data")

        var serializeCalls = 0
        let serializeFailure = ReminderProbeSnapshotWriter(run: run, pid: pid, directory: directory("unused"), encode: { _ in
            serializeCalls += 1; throw FixtureFailure.injected
        })
        serializeFailure.append(event(1)); serializeFailure.append(event(2))
        try check(serializeFailure.stopped && serializeCalls == 1, "serialization failure")
        passed.append("serialization failure is terminal")

        let mismatch = ReminderProbeSnapshotWriter(run: run, pid: 100, directory: directory("identity"))
        mismatch.append(event(1)); mismatch.append(event(2))
        try check(mismatch.stopped && mismatch.attempts == 0 && !FileManager.default.fileExists(atPath: directory("identity").path), "identity mismatch no file work")
        let gap = ReminderProbeSnapshotWriter(run: run, pid: pid, directory: directory("gap"))
        gap.append(event(2)); gap.append(event(1))
        try check(gap.stopped && gap.attempts == 0, "sequence mismatch no file work")
        passed.append("identity and sequence mismatches disable witness")

        let changed = ReminderProbeSnapshotWriter(run: run, pid: pid, directory: directory("changed"))
        changed.append(event(1))
        let changedFile = directory("changed").appendingPathComponent(run + ".json")
        try Data("replacement owner".utf8).write(to: changedFile, options: .atomic)
        changed.append(event(2)); changed.append(event(3))
        let changedBytes = try Data(contentsOf: changedFile)
        try check(changed.stopped && changed.attempts == 2 && changedBytes == Data("replacement owner".utf8), "changed inode preserved")
        passed.append("unexpected file identity disables witness")

        let target = directory("symlink-target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let linked = directory("symlink-directory")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: target)
        let linkedWriter = ReminderProbeSnapshotWriter(run: run, pid: pid, directory: linked)
        linkedWriter.append(event(1)); linkedWriter.append(event(2))
        let targetContents = try FileManager.default.contentsOfDirectory(atPath: target.path)
        try check(linkedWriter.stopped && targetContents.isEmpty, "directory symlink no writes")
        passed.append("symlink directory rejected")

        let report: [String: Any] = ["passed": passed, "passedCount": passed.count,
            "actualSynchronousTiming": ["writes": writer.successfulWrites, "totalNanoseconds": writer.totalWriteNanoseconds,
                "lastNanoseconds": writer.lastWriteNanoseconds],
            "timingScope": "Host fixture only. Serialization and writes perturb the marker call; no latency bound or iOS timing claim."]
        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try reportData.write(to: root.appendingPathComponent("writer-results.json"))
        print(String(decoding: reportData, as: UTF8.self))
    }
}

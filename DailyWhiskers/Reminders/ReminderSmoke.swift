#if DEBUG && CI_SMOKE_TESTING
import SwiftUI
#if DW_REMINDER_ENABLE_PROBE
import os
#endif

/// No system notification center is reachable through the offline UI seam.
/// This validates UI/adapter decisions, never OS permission or delivery.
@MainActor
enum ReminderSmoke {
    static var controlsEnabled: Bool { CISmokeMode.isEnabled && ProcessInfo.processInfo.arguments.contains("--ci-smoke-reminders") }
    static let directory: URL = {
        let supplied = ProcessInfo.processInfo.environment["DW_REMINDER_TEST_ID"].flatMap(UUID.init(uuidString:))
        return FileManager.default.temporaryDirectory.appendingPathComponent("ReminderFixtures/" + (supplied ?? UUID()).uuidString)
    }()
    static let client = ReminderSmokeClient(url: directory.appendingPathComponent("fake-center.json"))
    static func makeModel() -> ReminderModel {
        let model = ReminderModel(scheduler: ReminderScheduler(client: client,
            store: FileReminderJournalStore(directory: directory.appendingPathComponent("journal"))))
#if DW_REMINDER_ENABLE_PROBE
        ReminderEnableProbe.record(.ready, model: model, operations: 0)
#endif
        if ProcessInfo.processInfo.arguments.contains("--ci-smoke-reminder-cold-tap") {
            model.receiveTap(identifier: ReminderRequest.prefix + "old", destination: "today")
        }
        return model
    }
}

actor ReminderSmokeClient: ReminderNotificationClient {
    private struct State: Codable {
        var authorization = "notDetermined"
        var requests: [String: ReminderTarget] = [:]
        var prompts = 0
    }
    let url: URL
    private var state: State
    init(url: URL) {
        self.url = url
        state = (try? JSONDecoder().decode(State.self, from: Data(contentsOf: url))) ?? State()
    }
    private func save() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
    func authorization() -> ReminderAuthorization { ReminderAuthorization(rawValue: state.authorization) ?? .denied }
    func requestAlerts() throws { state.prompts += 1; state.authorization = "authorized"; try save() }
    func pendingRequests() -> [ReminderPendingRequest]? {
        state.requests.map { ReminderPendingRequest(ReminderRequest.make(id: $0.key, target: $0.value)) }
    }
    func delivered() -> Set<String> { [] }
    func add(id: String, target: ReminderTarget) throws { state.requests[id] = target; try save() }
    func removePending(_ ids: Set<String>) { for id in ids { state.requests.removeValue(forKey: id) }; try? save() }
    func removeDelivered(_ ids: Set<String>) { }
    func setAuthorization(_ value: ReminderAuthorization) throws { state.authorization = value.rawValue; try save() }
}

struct ReminderSmokeControls: View {
    @ObservedObject var model: ReminderModel
    var context = "root"
    var body: some View {
        HStack {
            Button("Test revoke") { Task { try? await ReminderSmoke.client.setAuthorization(.denied); await model.send(.refresh) } }
                .accessibilityIdentifier(context + "-reminder-test-revoke")
            Button("Test regrant") { Task { try? await ReminderSmoke.client.setAuthorization(.authorized); await model.send(.refresh) } }
                .accessibilityIdentifier(context + "-reminder-test-regrant")
            Button("Test reminder tap") { model.receiveTap(identifier: ReminderRequest.prefix + "old", destination: "today") }
                .accessibilityIdentifier(context + "-reminder-test-tap")
        }.font(.caption).buttonStyle(.bordered).background(.black)
    }
}
#if DW_REMINDER_ENABLE_PROBE
/// Local-only observability. Never log reminder times, content, paths or errors.
@MainActor
enum ReminderEnableProbe {
    enum Stage: String { case ready, bindingSetter, sendEntry, statusPublished, sendComplete }
    private static let logger = Logger(subsystem: "DailyWhiskers", category: "ReminderEnableProbe")
    private static let runID = ProcessInfo.processInfo.environment["DW_REMINDER_TEST_ID"]
        .flatMap(UUID.init(uuidString:))?.uuidString
    private static var sequence = 0
    private static var commandID = 0
#if targetEnvironment(simulator)
    private static var snapshotWriter: ReminderProbeSnapshotWriter?
#endif
    private static var isEnabled: Bool {
        runID != nil && ReminderSmoke.controlsEnabled &&
            ProcessInfo.processInfo.arguments.contains("--ci-smoke-reminder-enable-probe")
    }

    static func begin(_ command: ReminderCommand, model: ReminderModel, operations: Int) -> Int {
        guard isEnabled else { return 0 }
        commandID += 1
        record(.sendEntry, id: commandID, command: command, model: model, operations: operations)
        return commandID
    }

    static func record(_ stage: Stage, id: Int = 0, command: ReminderCommand? = nil,
                       model: ReminderModel, operations: Int = -1) {
        guard isEnabled, let runID else { return }
        let kind: String
        let requested: Int
        switch command {
        case .refresh: kind = "refresh"; requested = -1
        case .enable(let value): kind = "enable"; requested = value ? 1 : 0
        case .time: kind = "time"; requested = -1
        case nil: kind = "none"; requested = -1
        }
        sequence += 1
#if targetEnvironment(simulator)
        let event = ReminderProbeEvent(schema: 1, run: runID,
            pid: ProcessInfo.processInfo.processIdentifier, seq: sequence,
            tick: ProcessInfo.processInfo.systemUptime, stage: stage.rawValue,
            id: id, command: kind, requested: requested, enabled: model.status.enabled,
            authorization: model.status.authorization.rawValue, queued: model.status.queued,
            hasCoverage: model.status.coverageEnd != nil, hasMessage: model.status.message != nil,
            storageBlocked: model.status.storageBlocked, cleanupPending: model.status.cleanupPending,
            busy: model.busy, loaded: model.loaded, operations: operations)
        // A send ID pairs observations across await; it is not scheduler enqueue order.
        // statusPublished observes the returned value after the original @Published assignment.
        // The existing log transport is emitted first, before any snapshot file work.
        logger.notice("DWReminderEnableProbe schema=1 run=\(event.run, privacy: .public) pid=\(event.pid) seq=\(event.seq) tick=\(event.tick) stage=\(event.stage, privacy: .public) id=\(event.id) command=\(event.command, privacy: .public) requested=\(event.requested) enabled=\(event.enabled) authorization=\(event.authorization, privacy: .public) queued=\(event.queued) hasCoverage=\(event.hasCoverage) hasMessage=\(event.hasMessage) storageBlocked=\(event.storageBlocked) cleanupPending=\(event.cleanupPending) busy=\(event.busy) loaded=\(event.loaded) operations=\(event.operations)")
        if snapshotWriter == nil,
           let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            snapshotWriter = ReminderProbeSnapshotWriter(run: runID, pid: event.pid,
                directory: support.appendingPathComponent("ReminderEnableProbe", isDirectory: true))
        }
        snapshotWriter?.append(event)
#else
        // A send ID pairs observations across await; it is not scheduler enqueue order.
        // statusPublished observes the returned value after the original @Published assignment.
        logger.notice("DWReminderEnableProbe schema=1 run=\(runID, privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier) seq=\(sequence) tick=\(ProcessInfo.processInfo.systemUptime) stage=\(stage.rawValue, privacy: .public) id=\(id) command=\(kind, privacy: .public) requested=\(requested) enabled=\(model.status.enabled) authorization=\(model.status.authorization.rawValue, privacy: .public) queued=\(model.status.queued) hasCoverage=\(model.status.coverageEnd != nil) hasMessage=\(model.status.message != nil) storageBlocked=\(model.status.storageBlocked) cleanupPending=\(model.status.cleanupPending) busy=\(model.busy) loaded=\(model.loaded) operations=\(operations)")
#endif
    }
}
#endif
#endif

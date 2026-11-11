#if DEBUG && CI_SMOKE_TESTING
import SwiftUI

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
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        ReminderCommandTrace.record("session.start")
#endif
        let model = ReminderModel(scheduler: ReminderScheduler(client: client,
            store: FileReminderJournalStore(directory: directory.appendingPathComponent("journal"))))
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
#endif

#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
import Foundation

/// Disposable diagnostic only. Callers copy fixed metadata into bounded memory;
/// the independent utility queue alone encodes/exports it. Never flush or wait
/// in the binding, main actor, scheduler, or investigated journal I/O path.
enum ReminderCommandTrace {
    @TaskLocal static var commandID: String?
    private static let sessionID: String? = {
        let info = ProcessInfo.processInfo
        guard info.arguments.contains("--ci-smoke"),
              info.arguments.contains("--ci-smoke-reminders"),
              info.arguments.contains("--ci-diagnostic-reminder-trace"),
              let supplied = info.environment["DW_REMINDER_TEST_ID"],
              let id = UUID(uuidString: supplied) else { return nil }
        return id.uuidString
    }()
    static var isEnabled: Bool { sessionID != nil }
    private static let sink: Sink? = sessionID.map { Sink(sessionID: $0) }

    static func record(_ name: String, command: ReminderCommand? = nil,
                       status: ReminderStatus? = nil, enabled: Bool? = nil,
                       authorization: ReminderAuthorization? = nil,
                       busy: Bool? = nil, loaded: Bool? = nil, error: Error? = nil) {
        guard let sink else { return }
        var fields: [String: String] = [:]
        switch command {
        case .refresh?: fields["command"] = "refresh"
        case .enable(let value)?: fields["command"] = "enable"; fields["requested_enabled"] = String(value)
        case .time?: fields["command"] = "time" // Never export the user's time or any journal content.
        case nil: break
        }
        if let status {
            fields["enabled"] = String(status.enabled)
            fields["authorization"] = status.authorization.rawValue
            fields["storage_blocked"] = String(status.storageBlocked)
            fields["cleanup_pending"] = String(status.cleanupPending)
            fields["has_error"] = String(status.message != nil)
        }
        if let enabled { fields["enabled"] = String(enabled) }
        if let authorization { fields["authorization"] = authorization.rawValue }
        if let busy { fields["busy"] = String(busy) }
        if let loaded { fields["loaded"] = String(loaded) }
        if let error { fields["error_category"] = errorCategory(error) }
        sink.record(name, commandID: commandID, fields: fields)
    }

    private static func errorCategory(_ error: Error) -> String {
        if let storage = error as? ReminderStorageError {
            switch storage {
            case .unreadable: return "storage_unreadable"
            case .verification: return "storage_verification"
            case .quarantined: return "storage_quarantined"
            }
        }
        if error is CancellationError { return "cancelled" }
        let value = error as NSError
        // Codes/categories only. Never descriptions, userInfo, URLs, or paths.
        if value.domain == NSCocoaErrorDomain { return "cocoa_\(value.code)" }
        if value.domain == NSPOSIXErrorDomain { return "posix_\(value.code)" }
        return "other"
    }

    private struct Event: Encodable {
        let sequence: UInt64
        let monotonic_ns: UInt64
        let wall_time_unix: TimeInterval
        let command_id: String?
        let event: String
        let fields: [String: String]
    }

    private struct Snapshot: Encodable {
        let schema_version = 1
        let observation_scope = "initial_enable"
        let session_id: String
        let capture_started_monotonic_ns: UInt64
        let capture_complete_through_monotonic_ns: UInt64
        let capture_complete_through_wall_time_unix: TimeInterval
        let last_sequence: UInt64
        let events: [Event]
        let dropped_events: UInt64
        let event_limit = 1_024
        let export_attempt: Int
        let export_failures: Int
        let last_export_error_category: String?
        let export_complete = true
        let capture_closed: Bool
        let capture_end_reason: String
        // This timer bounds initial-enable diagnostics, not the full UI method.
        // Later revocation/regrant/disable may run after this capture has ended.
        let maximum_duration_seconds = 120
        let maximum_export_attempts = 481
    }

    private final class Sink: @unchecked Sendable {
        private let sessionID: String
        private let queue = DispatchQueue(label: "DailyWhiskers.ci.reminder-trace", qos: .utility)
        private let lock = NSLock()
        private let started = DispatchTime.now().uptimeNanoseconds
        private var events: [Event] = []
        private var sequence: UInt64 = 0
        private var dropped: UInt64 = 0
        private var closed = false
        private var timer: DispatchSourceTimer?
        // Export counters are confined to the utility queue, not the trace lock.
        private var attempts = 0
        private var failures = 0
        private var lastFailure: String?

        init(sessionID: String) {
            self.sessionID = sessionID
            events.reserveCapacity(1_024)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            self.timer = timer
            timer.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(50))
            timer.setEventHandler { [weak self] in self?.exportSnapshot() }
            timer.resume()
        }

        func record(_ name: String, commandID: String?, fields: [String: String]) {
            lock.lock(); defer { lock.unlock() }
            guard !closed else { return }
            sequence += 1
            guard events.count < 1_024 else { dropped += 1; return }
            events.append(Event(sequence: sequence, monotonic_ns: DispatchTime.now().uptimeNanoseconds,
                wall_time_unix: Date().timeIntervalSince1970, command_id: commandID, event: name, fields: fields))
        }

        private func exportSnapshot() {
            attempts += 1
            lock.lock()
            let through = DispatchTime.now().uptimeNanoseconds
            closed = through - started >= 120_000_000_000 || attempts >= 481
            let snapshot = Snapshot(session_id: sessionID, capture_started_monotonic_ns: started,
                capture_complete_through_monotonic_ns: through,
                capture_complete_through_wall_time_unix: Date().timeIntervalSince1970,
                last_sequence: sequence, events: events, dropped_events: dropped,
                export_attempt: attempts, export_failures: failures, last_export_error_category: lastFailure,
                capture_closed: closed, capture_end_reason: closed ? "capture_bound_reached" : "active")
            lock.unlock()
            if snapshot.capture_closed { timer?.cancel(); timer = nil }
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(snapshot)
                guard data.count <= 524_288 else { throw ExportError.payloadLimit }
                let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("DailyWhiskersCIDiagnostics", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appendingPathComponent("reminder-\(sessionID).json"), options: .atomic)
            } catch {
                failures += 1
                lastFailure = error is ExportError ? "payload_limit" : ReminderCommandTrace.errorCategory(error)
                print("DW_REMINDER_TRACE_EXPORT_FAILURE session=\(sessionID) attempt=\(attempts) category=\(lastFailure!)")
            }
        }
        private enum ExportError: Error { case payloadLimit }
    }
}
#endif

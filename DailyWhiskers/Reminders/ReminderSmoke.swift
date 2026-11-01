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
    func pending() -> Set<String>? { Set(state.requests.keys) }
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

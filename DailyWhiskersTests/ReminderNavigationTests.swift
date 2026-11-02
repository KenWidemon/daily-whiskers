import Foundation
import Testing
@testable import DailyWhiskers

private struct NoNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .notDetermined }
    func requestAlerts() async throws { }
    func pending() async -> Set<String>? { [] }
    func delivered() async -> Set<String> { [] }
    func add(id: String, target: ReminderTarget) async throws { }
    func removePending(_ ids: Set<String>) async { }
    func removeDelivered(_ ids: Set<String>) async { }
}

@Suite("Reminder response routing") @MainActor
struct ReminderNavigationTests {
    @Test func acceptsOnlyOwnedTodayTapAndRetainsColdLaunchRequestUntilConsumed() {
        let model = ReminderModel(scheduler: ReminderScheduler(client: NoNotifications(),
            store: FileReminderJournalStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))))
        model.receiveTap(identifier: "unrelated", destination: "today")
        #expect(model.todayRequest == nil)
        model.receiveTap(identifier: ReminderRequest.prefix + "old", destination: "old-card")
        #expect(model.todayRequest == nil)
        model.receiveTap(identifier: ReminderRequest.prefix + "old", destination: "today")
        let pending = model.todayRequest
        #expect(pending != nil)
        // No model refresh, scene or subscription was needed to retain the tap.
        #expect(model.todayRequest == pending)
        model.consumedTodayRequest()
        #expect(model.todayRequest == nil)
        model.receiveTap(identifier: ReminderRequest.prefix + "old", destination: "today")
        #expect(model.todayRequest != nil && model.todayRequest != pending)
    }
}

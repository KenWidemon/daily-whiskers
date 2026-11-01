import Foundation
import UserNotifications

enum ReminderAuthorization: String, Sendable {
    case notDetermined, denied, authorized, quiet
    var canSchedule: Bool { self == .authorized || self == .quiet }
}

protocol ReminderNotificationClient: Sendable {
    func authorization() async -> ReminderAuthorization
    func requestAlerts() async throws
    func pending() async -> Set<String>?
    func delivered() async -> Set<String>
    func add(id: String, target: ReminderTarget) async throws
    func removePending(_ ids: Set<String>) async
    func removeDelivered(_ ids: Set<String>) async
}

enum ReminderRequest {
    static let prefix = "dw004.reminder."
    static func owns(_ id: String) -> Bool { id.hasPrefix(prefix) }
    static func make(id: String, target: ReminderTarget) -> UNNotificationRequest {
        let calendar = ReminderCalendar.calendar(TimeZone(secondsFromGMT: 0)!)
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: target.date)
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        let content = UNMutableNotificationContent()
        content.title = "Daily Whiskers"
        content.body = "Your daily whisker of encouragement is ready."
        content.userInfo = ["dw004": "today"]
        // No sound/badge, category, push entitlement, or repeating trigger.
        return UNNotificationRequest(identifier: id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }
}

struct SystemReminderNotifications: ReminderNotificationClient {
    private var center: UNUserNotificationCenter { .current() }
    func authorization() async -> ReminderAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return settings.alertSetting == .enabled ? .authorized : .quiet
        case .provisional, .ephemeral: return .quiet
        @unknown default: return .denied
        }
    }
    func requestAlerts() async throws { _ = try await center.requestAuthorization(options: [.alert]) }
    func pending() async -> Set<String>? { Set(await center.pendingNotificationRequests().map(\.identifier)) }
    func delivered() async -> Set<String> { Set(await center.deliveredNotifications().map { $0.request.identifier }) }
    func add(id: String, target: ReminderTarget) async throws { try await center.add(ReminderRequest.make(id: id, target: target)) }
    func removePending(_ ids: Set<String>) async { center.removePendingNotificationRequests(withIdentifiers: Array(ids)) }
    func removeDelivered(_ ids: Set<String>) async { center.removeDeliveredNotifications(withIdentifiers: Array(ids)) }
}

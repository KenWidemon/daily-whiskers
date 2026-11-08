import Foundation
import UserNotifications

enum ReminderAuthorization: String, Sendable {
    case notDetermined, denied, authorized, quiet
    var canSchedule: Bool { self == .authorized || self == .quiet }
}

protocol ReminderNotificationClient: Sendable {
    func authorization() async -> ReminderAuthorization
    func requestAlerts() async throws
    func pendingRequests() async -> [ReminderPendingRequest]?
    func delivered() async -> Set<String>
    func add(id: String, target: ReminderTarget) async throws
    func removePending(_ ids: Set<String>) async
    func removeDelivered(_ ids: Set<String>) async
}

/// Plain values only: no notification-center objects escape the adapter.
/// Unknown trigger shapes remain visible so owned conflicts fail closed and
/// unrelated requests still count toward capacity.
struct ReminderPendingRequest: Equatable, Sendable {
    var id: String
    var calendarComponents: DateComponents?
    var repeats: Bool
    var title: String
    var subtitle: String
    var body: String
    var route: String?
    var unexpectedUserInfo: Bool
    var hasSound: Bool
    var badge: Int?
    var category: String
    var thread: String
    var targetContent: String?
    var launchImage: String
    var attachmentCount: Int
    var interruptionLevel: UInt
    var relevanceScore: Double
    var filterCriteria: String?

    init(_ request: UNNotificationRequest) {
        id = request.identifier
        calendarComponents = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
        repeats = request.trigger?.repeats ?? false
        let content = request.content
        title = content.title; subtitle = content.subtitle; body = content.body
        route = content.userInfo["dw004"] as? String
        unexpectedUserInfo = content.userInfo.count != 1 || route == nil
        hasSound = content.sound != nil; badge = content.badge?.intValue
        category = content.categoryIdentifier; thread = content.threadIdentifier
        targetContent = content.targetContentIdentifier
#if os(iOS)
        launchImage = content.launchImageName
#else
        launchImage = ""
#endif
        attachmentCount = content.attachments.count
        interruptionLevel = content.interruptionLevel.rawValue
        relevanceScore = content.relevanceScore
        filterCriteria = content.filterCriteria
        // Deprecated summaryArgument/count are ignored by supported OS versions.
    }
}

extension ReminderNotificationClient {
    func pending() async -> Set<String>? {
        await pendingRequests().map { Set($0.map(\.id)) }
    }
}

enum ReminderRequest {
    static let prefix = "dw004.reminder."
    static func owns(_ id: String) -> Bool { id.hasPrefix(prefix) }
    /// Ignore only benign UTC/calendar representation differences. Do not use
    /// nextTriggerDate(), which depends on the current clock and can hide edits.
    private static func normalized(_ parts: DateComponents?) -> DateComponents? {
        guard var parts, parts.calendar?.identifier == .gregorian,
              let zone = parts.timeZone,
              ["GMT", "UTC", "Etc/UTC", "Etc/GMT"].contains(zone.identifier),
              let calendarZone = parts.calendar?.timeZone,
              ["GMT", "UTC", "Etc/UTC", "Etc/GMT"].contains(calendarZone.identifier)
        else { return nil }
        parts.calendar = ReminderCalendar.calendar(TimeZone(secondsFromGMT: 0)!)
        parts.timeZone = TimeZone(secondsFromGMT: 0)!
        return parts
    }

    static func matches(_ request: ReminderPendingRequest, id: String, target: ReminderTarget) -> Bool {
        var actual = request
        var expected = ReminderPendingRequest(make(id: id, target: target))
        guard let components = normalized(actual.calendarComponents) else { return false }
        actual.calendarComponents = components
        expected.calendarComponents = normalized(expected.calendarComponents)
        return actual == expected
    }

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
    func pendingRequests() async -> [ReminderPendingRequest]? { await center.pendingNotificationRequests().map(ReminderPendingRequest.init) }
    func delivered() async -> Set<String> { Set(await center.deliveredNotifications().map { $0.request.identifier }) }
    func add(id: String, target: ReminderTarget) async throws { try await center.add(ReminderRequest.make(id: id, target: target)) }
    func removePending(_ ids: Set<String>) async { center.removePendingNotificationRequests(withIdentifiers: Array(ids)) }
    func removeDelivered(_ ids: Set<String>) async { center.removeDeliveredNotifications(withIdentifiers: Array(ids)) }
}

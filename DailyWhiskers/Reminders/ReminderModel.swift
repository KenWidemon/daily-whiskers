import SwiftUI
import UserNotifications

extension Notification.Name {
    static let reminderOpenToday = Notification.Name("DailyWhiskers.reminderOpenToday")
}

@MainActor
final class ReminderModel: ObservableObject {
    static let shared: ReminderModel = {
#if DEBUG && CI_SMOKE_TESTING
        if CISmokeMode.isEnabled { return ReminderSmoke.makeModel() }
#endif
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DailyWhiskers/Reminders", isDirectory: true)
        return ReminderModel(scheduler: ReminderScheduler(client: SystemReminderNotifications(),
            store: FileReminderJournalStore(directory: directory)))
    }()

    @Published private(set) var status = ReminderStatus()
    @Published private(set) var busy = false
    @Published private(set) var loaded = false
    @Published private(set) var todayRequest: UUID?
    private var operations = 0
    private let scheduler: ReminderScheduler

    init(scheduler: ReminderScheduler) { self.scheduler = scheduler }
    func send(_ command: ReminderCommand) async {
        operations += 1; busy = true
        status = await scheduler.submit(command)
        loaded = true
        operations -= 1; busy = operations > 0
    }

    func receiveTap(identifier: String, destination: String?) {
        guard ReminderRequest.owns(identifier), destination == "today" else { return }
        // UIKit activity sheets are presented by the window's root controller,
        // so recreating a SwiftUI navigation stack alone cannot dismiss them.
        NotificationCenter.default.post(name: .reminderOpenToday, object: nil)
        // Retained until the view consumes it, including a cold-launch callback
        // arriving before the SwiftUI hierarchy exists. Payload dates are ignored.
        todayRequest = UUID()
    }
    func consumedTodayRequest() { todayRequest = nil }
}

final class ReminderAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
#if DEBUG && CI_SMOKE_TESTING
        if CISmokeMode.isEnabled { return true }
#endif
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([]) // The visible app already provides today's content.
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { completionHandler(); return }
        let request = response.notification.request
        Task { @MainActor in
            ReminderModel.shared.receiveTap(identifier: request.identifier, destination: request.content.userInfo["dw004"] as? String)
            completionHandler()
        }
    }
}

import FirebaseCore
import SwiftUI

@main
struct DailyWhiskersApp: App {
    @UIApplicationDelegateAdaptor(ReminderAppDelegate.self) private var reminderDelegate
    @StateObject private var router = AppRouter()

    init() {
#if DEBUG && CI_SMOKE_TESTING && DW_SWITCH_OBSERVER
        DWSwitchObserver.install()
#endif
#if DEBUG && CI_SMOKE_TESTING
        if CISmokeMode.isEnabled { return }
#endif
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG && CI_SMOKE_TESTING
                if CISmokeMode.savedCardsFixtureURL != nil { SavedCardsLoadFixtureView() }
                else { RootView() }
#else
                RootView()
#endif
            }
                .environmentObject(router)
#if DEBUG && CI_SMOKE_TESTING
                .modifier(CISmokeStillnessFixture())
                // Reserve space for the offline marker so it cannot cover collection actions.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if CISmokeMode.isEnabled {
                        Text("Offline CI smoke")
                            .font(.system(size: 10))
                            .dynamicTypeSize(.medium)
                            .accessibilityIdentifier("ci-smoke-offline")
                            .allowsHitTesting(false)
                    }
                }
#endif
        }
    }
}

#if DEBUG && CI_SMOKE_TESTING && DW_SWITCH_OBSERVER
import OSLog
import ObjectiveC.runtime
import UIKit

/// Isolated diagnostic only. Adds a target; never replaces a control or handler.
/// Input IDs are temporal associations, not proof that an input caused a binding.
@MainActor
enum DWSwitchObserver {
    private static let logger = Logger(subsystem: "com.dailywhiskers.diagnostic", category: "DWSwitchObserver")
    private static var enabled = false
    private static var sequence = 0
    private static var nextNative = 0
    private static var nextInput = 0
    private static var nextCommand = 0
    private static var entries: [ObjectIdentifier: Entry] = [:]
    private static var active: Input?

    @MainActor final class Entry: NSObject {
        weak var control: UISwitch?
        let id: Int
        init(_ control: UISwitch, id: Int) { self.control = control; self.id = id }
        @objc func changed(_ sender: UISwitch) {
            guard control === sender else { invalidate("wrong-observer-sender"); return }
            if active?.control !== sender || active?.native != id {
                invalidate("valueChanged-native-unassociated")
            }
            audit()
            record("valueChanged native=\(id) \(context()) on=\(sender.isOn)")
        }
    }
    final class Input {
        weak var control: UISwitch?
        weak var window: UIWindow?
        let id: Int
        let native: Int
        var valid = true
        init(_ control: UISwitch, window: UIWindow, native: Int, id: Int) {
            self.control = control; self.window = window; self.native = native; self.id = id
        }
    }
    struct Command {
        let id: Int
        let input: Input?
    }

    static func install() {
        guard !enabled, CISmokeMode.isEnabled,
              ProcessInfo.processInfo.arguments.contains("--ci-smoke-reminders") else { return }
        enabled = true
        // Install an own-class override before exchanging an inherited method:
        // exchanging UIView.didMoveToWindow itself would affect every UIView.
        hook(UISwitch.self, #selector(UIView.didMoveToWindow), #selector(UISwitch.dw_observerMoved))
        hook(UIWindow.self, #selector(UIWindow.sendEvent(_:)), #selector(UIWindow.dw_observerEvent(_:)))
        record("installed limit=256")
    }
    private static func hook(_ type: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let inherited = class_getInstanceMethod(type, original),
              let alternate = class_getInstanceMethod(type, replacement) else {
            record("invalid missing-hook"); return
        }
        class_addMethod(type, original, method_getImplementation(inherited), method_getTypeEncoding(inherited))
        guard let own = class_getInstanceMethod(type, original) else { return }
        method_exchangeImplementations(own, alternate)
    }
    private static func record(_ fields: String) {
        guard enabled, sequence < 256 else { return }
        sequence += 1
        let line = "pid=\(ProcessInfo.processInfo.processIdentifier) seq=\(sequence) mono=\(ProcessInfo.processInfo.systemUptime) \(fields)"
        logger.notice("\(line, privacy: .public)")
        if sequence == 256 { logger.notice("invalid record-limit-reached") }
    }
    private static func context() -> String { context(active) }
    private static func context(_ input: Input?) -> String {
        "input=\(input?.id ?? 0) associatedNative=\(input?.native ?? 0) valid=\(input?.valid ?? false)"
    }
    private static func invalidate(_ reason: String) {
        invalidate(reason, input: active)
    }
    private static func invalidate(_ reason: String, input: Input?) {
        input?.valid = false
        record("invalid reason=\(reason) \(context(input))")
    }
    private static func present(_ entry: Entry) -> Bool {
        entry.control?.actions(forTarget: entry, forControlEvent: .valueChanged)?
            .contains(NSStringFromSelector(#selector(Entry.changed(_:)))) == true
    }
    private static func observe(_ control: UISwitch) -> Entry? {
        let key = ObjectIdentifier(control)
        if let entry = entries[key], entry.control === control { return entry }
        entries = entries.filter { $0.value.control != nil }
        guard nextNative < 64 else { invalidate("native-limit"); return nil }
        nextNative += 1
        let entry = Entry(control, id: nextNative)
        entries[key] = entry // UIControl does not retain targets; this retains only the observer.
        control.addTarget(entry, action: #selector(Entry.changed(_:)), for: .valueChanged)
        record("attached native=\(entry.id) registered=\(present(entry)) on=\(control.isOn) enabled=\(control.isEnabled)")
        if active != nil { invalidate("new-native-during-association") }
        return entry
    }
    static func moved(_ control: UISwitch) {
        guard enabled else { return }
        if control.window != nil {
            if let entry = observe(control) { record("window-attached native=\(entry.id)") }
        } else if let entry = entries[ObjectIdentifier(control)], entry.control === control {
            record("window-detached native=\(entry.id)")
            if active?.control === control { invalidate("associated-native-detached") }
        }
    }
    private static func scan(_ window: UIWindow) {
        var pending: [UIView] = [window]
        var visited = 0
        while let view = pending.popLast() {
            visited += 1
            guard visited <= 4096 else { invalidate("scan-limit"); return }
            if let control = view as? UISwitch { _ = observe(control) }
            pending.append(contentsOf: view.subviews)
        }
    }
    private static func audit() { audit(active) }
    private static func audit(_ input: Input?) {
        guard let input else { return }
        if let window = input.window { scan(window) }
        guard let control = input.control, let window = input.window,
              control.window === window,
              let entry = entries[ObjectIdentifier(control)], entry.control === control,
              entry.id == input.native, present(entry) else {
            invalidate("association-or-observer-lost", input: input); return
        }
    }
    private static func nativeAncestor(_ view: UIView?) -> UISwitch? {
        var node = view
        while let view = node {
            if let control = view as? UISwitch { return control }
            node = view.superview
        }
        return nil
    }
    static func before(_ event: UIEvent, window: UIWindow) {
        guard enabled else { return }
        scan(window)
        let touches = event.allTouches ?? []
        if touches.count > 1 { invalidate("multiple-touches"); return }
        for touch in touches {
            if touch.phase == .began {
                if active != nil { invalidate("subsequent-input"); active = nil }
                guard let control = nativeAncestor(touch.view), let entry = observe(control) else { continue }
                nextInput += 1
                active = Input(control, window: window, native: entry.id, id: nextInput)
            }
            guard let active else { continue }
            audit()
            if touch.phase == .cancelled { invalidate("touch-cancelled") }
            if let candidate = nativeAncestor(touch.view), candidate !== active.control {
                invalidate("touch-native-changed")
            }
            record("before phase=\(touch.phase.rawValue) eventTime=\(touch.timestamp) \(context()) on=\(active.control?.isOn ?? false) enabled=\(active.control?.isEnabled ?? false) hidden=\(active.control?.isHidden ?? true)")
        }
    }
    static func after(_ event: UIEvent, window: UIWindow) {
        guard enabled else { return }
        scan(window); audit()
        guard let active else { return }
        for touch in event.allTouches ?? [] {
            record("after phase=\(touch.phase.rawValue) eventTime=\(touch.timestamp) \(context()) on=\(active.control?.isOn ?? false)")
        }
        // Keep the weak association after .ended: binding callbacks can be deferred.
    }
    static func binding(_ value: Bool) {
        guard enabled else { return }
        audit()
        record("binding value=\(value) \(context())")
    }
    static func commandBegin(_ command: ReminderCommand) -> Command? {
        guard enabled, case .enable(let value) = command else { return nil }
        audit(); nextCommand += 1
        let command = Command(id: nextCommand, input: active)
        record("command-begin command=\(command.id) value=\(value) \(context(command.input))")
        return command
    }
    static func commandEnd(_ command: Command?, status: ReminderStatus, busy: Bool) {
        guard enabled, let command else { return }
        audit(command.input)
        record("command-end command=\(command.id) \(context(command.input)) enabled=\(status.enabled) busy=\(busy) error=\(status.message != nil) storageBlocked=\(status.storageBlocked)")
    }
}

extension UISwitch {
    @objc fileprivate func dw_observerMoved() {
        dw_observerMoved() // Original implementation, exactly once.
        DWSwitchObserver.moved(self)
    }
}
extension UIWindow {
    @objc fileprivate func dw_observerEvent(_ event: UIEvent) {
        DWSwitchObserver.before(event, window: self)
        dw_observerEvent(event) // Original implementation, exactly once.
        DWSwitchObserver.after(event, window: self)
    }
}
#endif

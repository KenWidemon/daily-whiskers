#if DEBUG && CI_SMOKE_TESTING
import Foundation
import ObjectiveC
import OSLog
import UIKit

/// Temporary, opt-in synthetic-fixture observations. Never force state or inject events.
/// Hooks forward UIKit's original implementation exactly once. Their presence and
/// synchronous logging may perturb timing; absent action logs alone do not prove no delivery.
enum StillnessDiagnosticTrace {
    static let enabled = CISmokeMode.isEnabled
        && ProcessInfo.processInfo.environment["DW_STILLNESS_DIAGNOSTICS"] == "1"
        && UUID(uuidString: ProcessInfo.processInfo.environment["DW_STILLNESS_TEST_ID"] ?? "") != nil
    private static let logger = Logger(subsystem: "com.ken.dailywhiskers.stillness-diagnostic", category: "trace")
    private static var started = false
    private static var sequence = 0
    private static var sheetVisible = false
    private static var preferences: UserDefaults?
    private static var observer: NSObjectProtocol?

    static func startIfRequested() {
        guard enabled, !started else { return }
        started = true
        let eventHook = exchange(UIApplication.self, #selector(UIApplication.sendEvent(_:)),
                                 #selector(UIApplication.dw127_sendEvent(_:)))
        let actionHook = exchange(UIControl.self, #selector(UIControl.sendAction(_:to:for:)),
                                  #selector(UIControl.dw127_sendAction(_:to:for:)))
        record("trace.install", ["eventHook": eventHook, "actionHook": actionHook])
    }

    private static func exchange(_ type: AnyClass, _ original: Selector, _ diagnostic: Selector) -> Bool {
        guard let first = class_getInstanceMethod(type, original),
              let second = class_getInstanceMethod(type, diagnostic),
              let firstType = method_getTypeEncoding(first), let secondType = method_getTypeEncoding(second),
              String(cString: firstType) == String(cString: secondType) else { return false }
        method_exchangeImplementations(first, second)
        return true
    }

    static func observePreferences(_ defaults: UserDefaults) {
        guard enabled else { return }
        preferences = defaults
        if observer == nil {
            // Observe notification receipt, not a claimed write timeline. Read only
            // the UUID fixture suite, never standard defaults or auth-field contents.
            observer = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main
            ) { _ in record("defaults.notification", ["stored": storedValue()]) }
        }
        record("defaults.attached", ["stored": storedValue()])
    }

    private static func storedValue() -> Any {
        preferences?.object(forKey: MotionPolicy.preferenceKey) ?? NSNull()
    }

    static func sheet(visible: Bool, value: Bool) {
        guard enabled else { return }
        sheetVisible = visible
        record(visible ? "sheet.appear" : "sheet.disappear", ["value": value, "stored": storedValue()])
    }

    static func binding(_ phase: String, old: Bool, requested: Bool) {
        record(phase, ["observed": old, "requested": requested, "stored": storedValue()])
    }

    static func stateChanged(old: Bool, new: Bool) {
        record("appStorage.change", ["old": old, "new": new, "stored": storedValue()])
    }

    static func touchEvent(_ event: UIEvent, phase: String) {
        guard enabled, sheetVisible, event.type == .touches else { return }
        for touch in event.allTouches ?? [] where [.began, .ended, .cancelled].contains(touch.phase) {
            var ancestry: [String] = []
            var view = touch.view
            for _ in 0..<6 {
                guard let current = view else { break }
                ancestry.append(NSStringFromClass(type(of: current)))
                view = current.superview
            }
            let point = touch.location(in: touch.window)
            record(phase, ["touchPhase": touch.phase.rawValue, "eventTime": event.timestamp,
                           "point": [point.x, point.y], "window": NSCoder.string(for: touch.window?.bounds ?? .zero),
                           "viewClasses": ancestry])
        }
    }

    static func controlAction(_ control: UIControl, action: Selector, event: UIEvent?, phase: String) {
        guard enabled, let toggle = control as? UISwitch else { return }
        record(phase, ["selector": NSStringFromSelector(action), "on": toggle.isOn,
                       "enabled": control.isEnabled, "eventTime": event?.timestamp ?? -1,
                       "frame": NSCoder.string(for: control.convert(control.bounds, to: control.window)),
                       "class": NSStringFromClass(type(of: control))])
    }

    private static func record(_ phase: String, _ fields: [String: Any]) {
        guard enabled else { return }
        sequence += 1
        var payload = fields
        payload["sequence"] = sequence
        payload["phase"] = phase
        payload["epoch"] = Date().timeIntervalSince1970
        payload["uptime"] = ProcessInfo.processInfo.systemUptime
        payload["pid"] = ProcessInfo.processInfo.processIdentifier
        payload["testID"] = ProcessInfo.processInfo.environment["DW_STILLNESS_TEST_ID"]
        payload["sheetVisible"] = sheetVisible
        payload["mainThread"] = Thread.isMainThread
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        logger.notice("DW_STILLNESS_DIAG \(text, privacy: .public)")
    }
}

fileprivate extension UIApplication {
    @objc dynamic func dw127_sendEvent(_ event: UIEvent) {
        StillnessDiagnosticTrace.touchEvent(event, phase: "touch.beforeDispatch")
        dw127_sendEvent(event)
        StillnessDiagnosticTrace.touchEvent(event, phase: "touch.afterDispatch")
    }
}

fileprivate extension UIControl {
    @objc dynamic func dw127_sendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
        StillnessDiagnosticTrace.controlAction(self, action: action, event: event, phase: "control.beforeAction")
        dw127_sendAction(action, to: target, for: event)
        StillnessDiagnosticTrace.controlAction(self, action: action, event: event, phase: "control.afterAction")
    }
}
#endif

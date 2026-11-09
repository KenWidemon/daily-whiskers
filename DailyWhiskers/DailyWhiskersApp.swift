import FirebaseCore
import SwiftUI

@main
struct DailyWhiskersApp: App {
    @UIApplicationDelegateAdaptor(ReminderAppDelegate.self) private var reminderDelegate
    @StateObject private var router = AppRouter()

    init() {
#if DEBUG && CI_SMOKE_TESTING
        DWSwitchCapture.installIfRequested()
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

#if DEBUG && CI_SMOKE_TESTING
import OSLog
import ObjectiveC.runtime
import UIKit

/// Temporary, opt-in CI input diagnostics. No labels, content, IDs or error payloads.
/// A hard record limit bounds overhead and unified-log volume per app launch.
enum DWSwitchCapture {
    private static let logger = Logger(subsystem: "com.dailywhiskers.diagnostic", category: "DWSwitchCapture")
    private static let requested = ProcessInfo.processInfo.environment["DW_SWITCH_CAPTURE"] == "1"
    private static let lock = NSLock()
    private static var count = 0
    private static var installed = false

    @MainActor static func installIfRequested() {
        guard requested, !installed else { return }
        installed = true
        let hooks: [(AnyClass, Selector, Selector)] = [
            (UIWindow.self, #selector(UIWindow.sendEvent(_:)), #selector(UIWindow.dw_captureSendEvent(_:))),
            (UIControl.self, #selector(UIControl.sendAction(_:to:for:)), #selector(UIControl.dw_captureSendAction(_:to:for:)))
        ]
        for (type, original, replacement) in hooks {
            guard let first = class_getInstanceMethod(type, original),
                  let second = class_getInstanceMethod(type, replacement) else {
                record("install missing hook")
                continue
            }
            method_exchangeImplementations(first, second)
        }
        record("installed limit=600")
    }

    static func record(_ message: String) {
        guard requested else { return }
        lock.lock()
        guard count < 600 else { lock.unlock(); return }
        count += 1
        let sequence = count
        lock.unlock()
        logger.notice("seq=\(sequence) \(message, privacy: .public)")
        if sequence == 600 { logger.notice("capture limit reached") }
    }

    @MainActor static func ancestry(_ view: UIView?) -> String {
        var node = view
        var parts: [String] = []
        for _ in 0..<8 {
            guard let current = node else { break }
            var part = "\(NSStringFromClass(type(of: current))) hidden=\(current.isHidden) interaction=\(current.isUserInteractionEnabled) alpha=\(current.alpha)"
            if let control = current as? UIControl {
                part += " enabled=\(control.isEnabled) tracking=\(control.isTracking) highlighted=\(control.isHighlighted)"
            }
            if let toggle = current as? UISwitch { part += " on=\(toggle.isOn)" }
            parts.append(part)
            node = current.superview
        }
        return parts.joined(separator: " <- ")
    }
}

extension UIWindow {
    @objc fileprivate func dw_captureSendEvent(_ event: UIEvent) {
        if let touches = event.allTouches {
            for touch in touches.prefix(4) {
                let point = touch.location(in: self)
                DWSwitchCapture.record("window receive phase=\(touch.phase.rawValue) x=\(point.x) y=\(point.y) view=\(DWSwitchCapture.ancestry(touch.view))")
            }
        }
        // Swizzling routes this call to the original implementation exactly once.
        dw_captureSendEvent(event)
    }
}

extension UIControl {
    @objc fileprivate func dw_captureSendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
        DWSwitchCapture.record("control sendAction event=\(event != nil) control=\(DWSwitchCapture.ancestry(self))")
        dw_captureSendAction(action, to: target, for: event)
    }
}
#endif

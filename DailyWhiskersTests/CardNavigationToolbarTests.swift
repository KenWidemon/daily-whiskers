import SwiftUI
import UIKit
import Testing
@testable import DailyWhiskers

@Suite("Toolbar configuration revisions", .serialized) @MainActor
struct CardNavigationToolbarTests {
    private func configuration(_ action: UIAction = UIAction(title: "Save") { _ in },
                               settings: Bool = true, enabled: Bool = true,
                               focus: Binding<Bool> = .constant(false)) -> CardNavigationToolbar {
        let item = CardNavigationToolbar.Item(identifier: "options", label: "Options", image: "ellipsis",
                                              enabled: enabled, menu: UIMenu(children: [action]))
        return CardNavigationToolbar(options: item, settings: settings ? item : nil,
            export: nil, onShareComplete: { _ in }, optionsFocused: focus, settingsFocused: .constant(false))
    }

    private func mount(_ controller: CardNavigationToolbar.Controller) throws -> (UIWindow, UIViewController, UIWindow?) {
        let host = UIViewController()
        host.addChild(controller)
        host.view.addSubview(controller.view)
        controller.didMove(toParent: host)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UINavigationController(rootViewController: host)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        controller.updateItems()
        return (window, host, previousKeyWindow)
    }

    @Test func unchangedCallbacksSkipWritesButFreshClosuresAndStateApply() throws {
        var invoked = 0
        let controller = CardNavigationToolbar.Controller()
        controller.configuration = configuration(UIAction(title: "Save") { _ in invoked = 1 })
        controller.updateItems() // Off-window guard must not mark the revision applied.
        let (window, host, previousKeyWindow) = try mount(controller)
        defer { window.isHidden = true; previousKeyWindow?.makeKeyAndVisible() }
        let item = try #require(host.navigationItem.rightBarButtonItems?.last)
        // A sentinel distinguishes an omitted setter from repeated same-value writes.
        item.accessibilityHint = "sentinel"
        controller.updateItems()
        #expect(item.accessibilityHint == "sentinel")
        controller.configuration = configuration(UIAction(title: "Save") { _ in invoked = 2 }, enabled: false)
        controller.updateItems()
        #expect(item.accessibilityHint == "")
        #expect(!item.isEnabled)
        let action = try #require(item.menu?.children.first as? UIAction)
        let button = UIButton()
        button.addAction(action, for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        #expect(invoked == 2)
    }

    @Test func settingsPresenceAttachmentAndFocusAreNotSuppressed() throws {
        var focused = false
        let binding = Binding(get: { focused }, set: { focused = $0 })
        let controller = CardNavigationToolbar.Controller()
        controller.configuration = configuration(focus: binding)
        let (window, host, previousKeyWindow) = try mount(controller)
        defer { window.isHidden = true; previousKeyWindow?.makeKeyAndVisible() }
        #expect(host.navigationItem.rightBarButtonItems?.count == 2)
        let anchor = try #require(controller.view as? DailyCardShareAnchor)
        anchor.barButtonItem = nil
        controller.viewWillDisappear(false)
        #expect(host.navigationItem.rightBarButtonItems == nil)
        focused = true
        controller.updateItems()
        #expect(!focused)
        #expect(anchor.barButtonItem === host.navigationItem.rightBarButtonItems?.last)
        #expect(host.navigationItem.rightBarButtonItems?.count == 2)
        controller.configuration = configuration(settings: false)
        controller.updateItems()
        #expect(host.navigationItem.rightBarButtonItems?.count == 1)
        controller.configuration = configuration()
        controller.updateItems()
        #expect(host.navigationItem.rightBarButtonItems?.count == 2)
    }

    @Test func coalescedConfigurationsApplyTheLatestAction() async throws {
        var invoked = 0
        let controller = CardNavigationToolbar.Controller()
        controller.configuration = configuration()
        let (window, host, previousKeyWindow) = try mount(controller)
        defer { window.isHidden = true; previousKeyWindow?.makeKeyAndVisible() }
        controller.configuration = configuration(UIAction(title: "Save") { _ in invoked = 1 })
        controller.scheduleUpdate()
        controller.configuration = configuration(UIAction(title: "Save") { _ in invoked = 2 })
        controller.scheduleUpdate()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        let action = try #require(host.navigationItem.rightBarButtonItems?.last?.menu?.children.first as? UIAction)
        let button = UIButton()
        button.addAction(action, for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        #expect(invoked == 2)
    }

    @Test func ownerChangeReappliesUnchangedConfiguration() throws {
        let controller = CardNavigationToolbar.Controller()
        controller.configuration = configuration()
        let (firstWindow, firstHost, originalKeyWindow) = try mount(controller)
        defer { firstWindow.isHidden = true; originalKeyWindow?.makeKeyAndVisible() }
        let item = try #require(firstHost.navigationItem.rightBarButtonItems?.last)
        item.accessibilityHint = "sentinel"
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        let (secondWindow, secondHost, previousKeyWindow) = try mount(controller)
        defer { secondWindow.isHidden = true; previousKeyWindow?.makeKeyAndVisible() }
        #expect(secondHost.navigationItem.rightBarButtonItems?.last === item)
        #expect(item.accessibilityHint == "")
    }
}

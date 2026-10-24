import SwiftUI
import UIKit

/// Use native bar items, rather than SwiftUI-hosted labels, so UIKit owns the
/// expanded navigation-bar hit region. This controller adds no visible content.
struct CardNavigationToolbar: UIViewControllerRepresentable {
    struct Item {
        let identifier: String
        let label: String
        var hint: String = ""
        var value: String = ""
        let image: String
        var enabled = true
        var hiddenFromAccessibility = false
        let menu: UIMenu
    }

    let options: Item
    var settings: Item?
    let export: DailyCardShareExport?
    let onShareComplete: (Bool) -> Void
    @Binding var optionsFocused: Bool
    @Binding var settingsFocused: Bool

    static func action(_ title: String, identifier: String? = nil, image: UIImage? = nil,
                       hint: String = "", value: String = "", disabled: Bool = false,
                       destructive: Bool = false, perform: @escaping () -> Void) -> UIAction {
        var attributes: UIMenuElement.Attributes = []
        if disabled { attributes.insert(.disabled) }
        if destructive { attributes.insert(.destructive) }
        let action = UIAction(title: title, image: image, attributes: attributes) { _ in perform() }
        action.accessibilityIdentifier = identifier
        action.accessibilityHint = hint
        action.accessibilityValue = value
        return action
    }

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.configuration = self
        controller.scheduleUpdate()
    }

    final class Controller: UIViewController {
        var configuration: CardNavigationToolbar?
        private let optionsItem = UIBarButtonItem()
        private let settingsItem = UIBarButtonItem()
        private weak var owner: UIViewController?
        private var updateScheduled = false
        private var anchor: DailyCardShareAnchor { view as! DailyCardShareAnchor }

        override func loadView() {
            let anchor = DailyCardShareAnchor()
            anchor.backgroundColor = .clear
            anchor.isUserInteractionEnabled = false
            anchor.accessibilityElementsHidden = true
            view = anchor
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            scheduleUpdate()
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            scheduleUpdate()
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            scheduleUpdate()
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let owner, owner.navigationItem.rightBarButtonItems?.contains(where: { $0 === optionsItem }) == true {
                owner.navigationItem.rightBarButtonItems = nil
            }
        }
        func scheduleUpdate() {
            guard !updateScheduled else { return }
            updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                self.updateItems()
            }
        }
        private func updateItems() {
            guard let configuration, isViewLoaded, view.window != nil else { return }
            // Traverse only public containment. Do not inspect SwiftUI host classes
            // or private navigation-bar subviews.
            var current: UIViewController? = self
            while let child = current, let parent = child.parent {
                if let navigation = parent as? UINavigationController {
                    guard navigation.topViewController === child else { return }
                    owner = child
                    break
                }
                current = parent
            }
            guard let owner else { return }
            update(optionsItem, from: configuration.options)
            var items = [optionsItem]
            if let settings = configuration.settings {
                update(settingsItem, from: settings)
                items.insert(settingsItem, at: 0)
            }
            let existing = owner.navigationItem.rightBarButtonItems ?? []
            if existing.count != items.count || !zip(existing, items).allSatisfy({ $0 === $1 }) {
                owner.navigationItem.rightBarButtonItems = items
            }
            anchor.barButtonItem = optionsItem
            anchor.update(export: configuration.export, onComplete: configuration.onShareComplete)
            if configuration.export == nil, owner.presentedViewController == nil {
                if configuration.optionsFocused {
                    UIAccessibility.post(notification: .layoutChanged, argument: optionsItem)
                    configuration.optionsFocused = false
                } else if configuration.settingsFocused {
                    UIAccessibility.post(notification: .layoutChanged, argument: settingsItem)
                    configuration.settingsFocused = false
                }
            }
        }
        private func update(_ item: UIBarButtonItem, from state: Item) {
            item.image = UIImage(systemName: state.image)
            item.menu = state.menu
            item.isEnabled = state.enabled
            item.accessibilityIdentifier = state.identifier
            item.accessibilityLabel = state.label
            item.accessibilityHint = state.hint
            item.accessibilityValue = state.value
            item.accessibilityElementsHidden = state.hiddenFromAccessibility
        }
    }
}

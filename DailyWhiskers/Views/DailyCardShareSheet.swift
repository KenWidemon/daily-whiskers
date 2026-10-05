import LinkPresentation
import SwiftUI
import UIKit

/// A view-only toolbar anchor keeps navigation rotation under SwiftUI control.
/// Present the activity controller from this view's window, never as a toolbar child.
struct DailyCardShareSheet: UIViewRepresentable {
    let export: DailyCardShareExport?
    let onComplete: (Bool) -> Void

    func makeUIView(context: Context) -> DailyCardShareAnchor {
        let anchor = DailyCardShareAnchor()
        anchor.backgroundColor = .clear
        anchor.isUserInteractionEnabled = false
        return anchor
    }

    func updateUIView(_ anchor: DailyCardShareAnchor, context: Context) {
        anchor.update(export: export, onComplete: onComplete)
    }
}

final class DailyCardShareAnchor: UIView, UIPopoverPresentationControllerDelegate {
    private var pendingExport: DailyCardShareExport?
    private var activeID: UUID?
    private weak var activityController: UIActivityViewController?
    private var onComplete: ((Bool) -> Void)?

    func update(export: DailyCardShareExport?, onComplete: @escaping (Bool) -> Void) {
        pendingExport = export
        self.onComplete = onComplete
        presentIfReady()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        presentIfReady()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the anchor current across rotation and split-view resizing.
        activityController?.popoverPresentationController?.sourceRect = bounds
        presentIfReady()
    }

    private func presentIfReady() {
        guard let export = pendingExport, activeID == nil,
              let presenter = window?.rootViewController,
              presenter.presentedViewController == nil else { return }
        activeID = export.id
        let source = DailyCardShareImageSource(image: export.image)
        let controller = UIActivityViewController(activityItems: [source, export.text], applicationActivities: nil)
        controller.completionWithItemsHandler = { [weak self, weak controller] _, _, _, error in
            // Some activities finish during their dismissal transition. Return focus
            // or show retry only after that transition has completed.
            if let controller, controller.isBeingDismissed, let transition = controller.transitionCoordinator {
                transition.animate(alongsideTransition: nil) { _ in
                    self?.complete(id: export.id, failed: error != nil)
                }
            } else {
                self?.complete(id: export.id, failed: error != nil)
            }
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            controller.modalPresentationStyle = .popover
            controller.popoverPresentationController?.sourceView = self
            controller.popoverPresentationController?.sourceRect = bounds
            controller.popoverPresentationController?.permittedArrowDirections = [.up, .down]
        } else {
            controller.modalPresentationStyle = .pageSheet
        }
        // A toolbar host does not cover the screen. Present from its own window's
        // root controller so the compact sheet receives normal modal hit testing.
        activityController = controller
        presenter.present(controller, animated: true)
        controller.presentationController?.delegate = self
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let activeID else { return }
        complete(id: activeID, failed: false)
    }

    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        guard let activeID else { return }
        complete(id: activeID, failed: false)
    }

    private func complete(id: UUID, failed: Bool) {
        guard activeID == id else { return }
        activeID = nil
        activityController = nil
        pendingExport = nil
        onComplete?(failed)
    }
}

/// The system sheet previews the artwork instead of choosing the text companion
/// as its header. No URL is provided and no preview is fetched from the network.
final class DailyCardShareImageSource: NSObject, UIActivityItemSource {
    private let image: UIImage

    init(image: UIImage) { self.image = image }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        image
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = "Daily Whiskers"
        metadata.imageProvider = NSItemProvider(object: image)
        metadata.iconProvider = metadata.imageProvider
        return metadata
    }
}

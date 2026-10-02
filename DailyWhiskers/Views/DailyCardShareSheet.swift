import SwiftUI
import UIKit

/// UIKit owns destination selection and sending. The app never posts a card itself.
struct DailyCardShareSheet: UIViewControllerRepresentable {
    let export: DailyCardShareExport
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [export.image, export.text], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, error in
            onComplete(error != nil)
        }
        // SwiftUI presents this as a sheet on both device families. Supply an anchor
        // too, so UIKit has a valid source if it adapts the presentation to a popover.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.maxY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

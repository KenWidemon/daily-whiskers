import SwiftUI
import UIKit

/// A value captured from the displayed card, never a new date-based selection.
struct DailyCardShareSnapshot {
    let imageName: String
    let quote: String
    let vibe: String?

    init(card: DailyCard) {
        imageName = card.imageName
        quote = card.quote
        vibe = card.vibe.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    var companionText: String {
        ["“\(quote)”", vibe.map { "Vibe: \($0)" }, "Daily Whiskers"]
            .compactMap { $0 }.joined(separator: "\n\n")
    }
}

struct DailyCardShareExport: Identifiable {
    let id = UUID()
    let image: UIImage
    let text: String
}

enum DailyCardShareError: Error {
    case missingArtwork, contentTooLarge
}

/// Fixed pixel width and bounded height keep export memory independent of device scale.
/// Drawing into a fresh bitmap excludes source metadata, account data, and app chrome.
@MainActor
struct DailyCardShareRenderer {
    static let width: CGFloat = 1080
    static let maximumHeight: CGFloat = 2400
    static let quoteFont = UIFont(descriptor: UIFont.systemFont(ofSize: 48, weight: .semibold)
        .fontDescriptor.withDesign(.serif) ?? UIFont.systemFont(ofSize: 48, weight: .semibold).fontDescriptor, size: 48)

    struct Layout {
        let size: CGSize
        let artwork: CGRect
        let quote: CGRect
        let vibe: CGRect?
        let branding: CGRect
    }

    static func attributes(font: UIFont, color: UIColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 8
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    static func layout(for snapshot: DailyCardShareSnapshot) throws -> Layout {
        // Reject unreasonable future content before allocating or measuring it.
        guard snapshot.quote.utf16.count <= 4000, (snapshot.vibe?.utf16.count ?? 0) <= 200 else {
            throw DailyCardShareError.contentTooLarge
        }
        let textWidth: CGFloat = 936
        func height(_ text: String, font: UIFont) -> CGFloat {
            ceil((text as NSString).boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes(font: font, color: .white), context: nil
            ).height) + 8
        }
        let artwork = CGRect(x: 60, y: 60, width: 960, height: 1440)
        let quote = CGRect(x: 72, y: artwork.maxY + 44, width: textWidth,
                           height: height("“\(snapshot.quote)”", font: quoteFont))
        let vibe = snapshot.vibe.map {
            CGRect(x: 72, y: quote.maxY + 28, width: textWidth,
                   height: height($0, font: .systemFont(ofSize: 30, weight: .medium)))
        }
        let branding = CGRect(x: 72, y: (vibe?.maxY ?? quote.maxY) + 48,
                              width: textWidth, height: 44)
        let size = CGSize(width: width, height: branding.maxY + 56)
        guard size.height <= maximumHeight else { throw DailyCardShareError.contentTooLarge }
        return Layout(size: size, artwork: artwork, quote: quote, vibe: vibe, branding: branding)
    }

    static func render(_ snapshot: DailyCardShareSnapshot) throws -> DailyCardShareExport {
        let layout = try layout(for: snapshot)
        guard let artwork = UIImage(named: snapshot.imageName) else {
            throw DailyCardShareError.missingArtwork
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: layout.size, format: format).image { context in
            UIColor(red: 0.055, green: 0.043, blue: 0.08, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: layout.size))
            context.cgContext.saveGState()
            UIBezierPath(roundedRect: layout.artwork, cornerRadius: 28).addClip()
            // Fit the entire approved artwork; never crop the cat to fit text.
            let scale = min(layout.artwork.width / artwork.size.width, layout.artwork.height / artwork.size.height)
            let size = CGSize(width: artwork.size.width * scale, height: artwork.size.height * scale)
            artwork.draw(in: CGRect(x: layout.artwork.midX - size.width / 2,
                                    y: layout.artwork.midY - size.height / 2,
                                    width: size.width, height: size.height))
            context.cgContext.restoreGState()
            ("“\(snapshot.quote)”" as NSString).draw(in: layout.quote,
                withAttributes: attributes(font: quoteFont, color: .white))
            if let vibe = snapshot.vibe, let rect = layout.vibe {
                (vibe as NSString).draw(in: rect, withAttributes: attributes(
                    font: .systemFont(ofSize: 30, weight: .medium),
                    color: UIColor(red: 0.88, green: 0.80, blue: 0.96, alpha: 1)))
            }
            ("Daily Whiskers" as NSString).draw(in: layout.branding, withAttributes: attributes(
                font: .systemFont(ofSize: 32, weight: .medium),
                color: UIColor(red: 0.94, green: 0.81, blue: 0.57, alpha: 1)))
        }
        return DailyCardShareExport(image: image, text: snapshot.companionText)
    }
}

@MainActor
final class DailyCardShareState: ObservableObject {
    @Published private(set) var isRendering = false
    @Published var export: DailyCardShareExport?
    @Published var hasError = false
    private(set) var snapshot: DailyCardShareSnapshot?
    private var activityFailed = false
    private let render: @MainActor (DailyCardShareSnapshot) throws -> DailyCardShareExport

    init(render: (@MainActor (DailyCardShareSnapshot) throws -> DailyCardShareExport)? = nil) {
        self.render = render ?? DailyCardShareRenderer.render
    }

    func start(card: DailyCard) async {
        guard !isRendering, export == nil else { return }
        snapshot = DailyCardShareSnapshot(card: card)
        await prepare()
    }

    func retry() async {
        guard !isRendering, export == nil, snapshot != nil else { return }
        await prepare()
    }

    private func prepare() async {
        guard let snapshot else { return }
        isRendering = true
        hasError = false
        // Give SwiftUI an opportunity to announce progress before synchronous drawing.
        await Task.yield()
        defer { isRendering = false }
        do {
            export = try autoreleasepool { try render(snapshot) }
        } catch {
            hasError = true
        }
    }

    func completeActivity(failed: Bool) {
        // Present an error only after the sheet has finished dismissing.
        activityFailed = failed
        export = nil
    }

    func sheetDismissed() {
        finish(failed: activityFailed)
        activityFailed = false
    }

    func finish(failed: Bool = false) {
        export = nil
        hasError = failed
        if !failed { snapshot = nil }
    }
}

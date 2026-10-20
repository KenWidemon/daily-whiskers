import SwiftUI
import UIKit

/// A value captured from the displayed card, never a new date-based selection.
struct DailyCardShareSnapshot {
    let archetype: String
    let imageName: String
    let retainedArtwork: Data?
    let quote: String
    let vibe: String?

    init(card: DailyCard) {
        archetype = card.archetype
        retainedArtwork = try? BundledCardArtwork.bytes(for: card)
        imageName = card.imageName
        quote = card.quote
        vibe = card.vibe.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    init(retained: RetainedCard) {
        archetype = retained.snapshot.archetype
        imageName = ""
        retainedArtwork = retained.artwork
        quote = retained.snapshot.quote
        vibe = retained.snapshot.vibe.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
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
    case missingArtwork, missingLogo, contentTooLarge, renderingFailed
}

/// Rendering is independent of viewport, scroll position and the user's text size.
/// All content is frozen before yielding; no mutable asset lookup occurs during render.
@MainActor
struct DailyCardShareRenderer {
    static let width: CGFloat = 1080
    static let maximumHeight: CGFloat = 2400
    static let scale: CGFloat = 3
    static let logoResource = "Daily_Whiskers_App_Icon_FINAL_cropped"
    static let watermarkSize: CGFloat = 24
    static let watermarkOpacity = 0.45

    /// Faithful monochrome treatment of the packaged final icon, not a redrawn mark.
    /// The approved white cat is separated from its saturated purple tile by the green
    /// channel (including its antialiased whiskers and facial cutouts). Coordinates and
    /// silhouette come directly from the source pixels; RGB becomes white, tile alpha zero.
    static let watermark: UIImage? = {
        guard let url = Bundle.main.url(forResource: logoResource, withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path)?.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = buffer.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let coverage = min(1, max(0, (Double(pixels[i + 1]) - 128) / 64))
                let alpha = UInt8((coverage * coverage * (3 - 2 * coverage) * 255).rounded())
                // Premultiplied white; preserve the source geometry without any tracing.
                pixels[i] = alpha; pixels[i + 1] = alpha; pixels[i + 2] = alpha; pixels[i + 3] = alpha
            }
            return context.makeImage().map { UIImage(cgImage: $0) }
        }
    }()

    static func render(_ snapshot: DailyCardShareSnapshot) throws -> DailyCardShareExport {
        guard snapshot.quote.utf16.count <= 4000, (snapshot.vibe?.utf16.count ?? 0) <= 200 else {
            throw DailyCardShareError.contentTooLarge
        }
        guard let bytes = snapshot.retainedArtwork, let artwork = UIImage(data: bytes) else {
            throw DailyCardShareError.missingArtwork
        }
        guard let logo = watermark else { throw DailyCardShareError.missingLogo }
        let theme = ArchetypeTheme.forArchetype(snapshot.archetype)
        let content = VStack(spacing: 16) {
            RitualCardPresentation(data: DailyCardData(archetype: snapshot.archetype,
                imageName: "", quote: snapshot.quote, vibe: snapshot.vibe ?? ""),
                artwork: artwork, compact: true)
            // Dedicated footer keeps the monochrome approved mark off artwork and text.
            Image(uiImage: logo).resizable().scaledToFit()
                .frame(width: watermarkSize, height: watermarkSize)
                .opacity(watermarkOpacity)
        }
        .padding(18)
        .frame(width: width / scale)
        .background(LinearGradient(colors: [theme.bgTop, theme.bgBottom], startPoint: .top, endPoint: .bottom))
        .environment(\.dynamicTypeSize, .large)
        .environment(\.colorScheme, .dark)
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.locale, Locale(identifier: "en_US"))
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: width / scale, height: nil)
        renderer.scale = scale
        renderer.isOpaque = true
        var image: UIImage?
        var tooLarge = false
        // Measure before allocating the bitmap; do not clip or shrink oversized text.
        renderer.render(rasterizationScale: scale) { size, draw in
            let pixels = CGSize(width: width, height: ceil(size.height * scale))
            guard pixels.height <= maximumHeight else { tooLarge = true; return }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            format.preferredRange = .standard
            image = UIGraphicsImageRenderer(size: pixels, format: format).image { context in
                UIColor(theme.bgBottom).setFill()
                context.fill(CGRect(origin: .zero, size: pixels))
                context.cgContext.scaleBy(x: scale, y: scale)
                // ImageRenderer's drawing closure uses Core Graphics' bottom-left origin.
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                draw(context.cgContext)
            }
        }
        if tooLarge { throw DailyCardShareError.contentTooLarge }
        guard let image else { throw DailyCardShareError.renderingFailed }
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

    func start(retained: RetainedCard) async {
        guard !isRendering, export == nil else { return }
        do { try retained.snapshot.validate(artwork: retained.artwork) }
        catch { hasError = true; return }
        snapshot = DailyCardShareSnapshot(retained: retained)
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
#if DEBUG && CI_SMOKE_TESTING
            try CISmokeMode.failShareIfRequested()
#endif
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

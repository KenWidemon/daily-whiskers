import Foundation
import ImageIO
import Testing
import UIKit
@testable import DailyWhiskers

@Suite("Daily card sharing", .serialized)
@MainActor
struct DailyCardShareTests {
    private func card(image: String = DailyContentProvider.fallbackCard.imageName,
                      quote: String = "Take a gentle breath.", vibe: String? = "Calm") -> DailyCard {
        DailyCard(id: "internal-content-id", archetype: "cozy", imageName: image, quote: quote, vibe: vibe)
    }

    @Test("Snapshot survives foreground midnight rollover and uses the displayed card")
    func rollover() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let cards = [card(quote: "Yesterday"), card(quote: "Today")]
        var content = DailyContentState(provider: DailyContentProvider(calendar: calendar,
            manifest: DailyContentManifest(cards: cards)))
        let formatter = ISO8601DateFormatter()
        content.refresh(at: try #require(formatter.date(from: "2026-09-30T23:59:59Z")))
        let displayed = try #require(content.currentCard)
        let share = DailyCardShareState { snapshot in
            DailyCardShareExport(image: UIImage(), text: snapshot.companionText)
        }
        let rendering = Task { await share.start(card: displayed) }
        content.refresh(at: try #require(formatter.date(from: "2026-10-01T00:00:01Z")))
        await rendering.value
        #expect(content.currentCard?.quote != displayed.quote)
        #expect(share.snapshot?.quote == displayed.quote)
        #expect(share.export?.text.contains(displayed.quote) == true)
        #expect(share.snapshot?.imageName == displayed.imageName)
    }

    @Test("Text companion includes the exact quote and optional vibe, without internal identifiers")
    func companion() {
        let snapshot = DailyCardShareSnapshot(card: card(quote: "Breathe.\nYou’re here 🐈", vibe: "Still"))
        #expect(snapshot.companionText == "“Breathe.\nYou’re here 🐈”\n\nVibe: Still\n\nDaily Whiskers")
        #expect(!snapshot.companionText.contains("internal-content-id"))
        #expect(!snapshot.companionText.contains(snapshot.imageName))
        #expect(!DailyCardShareSnapshot(card: card(vibe: " \n ")).companionText.contains("Vibe:"))
        #expect(!DailyCardShareSnapshot(card: card(vibe: nil)).companionText.contains("Vibe:"))
    }

    @Test("Every supported quote and artwork renders at bounded pixel dimensions without text clipping")
    func supportedContent() throws {
        let url = try #require(Bundle.main.url(forResource: "daily_whiskers_content", withExtension: "json"))
        let manifest = try JSONDecoder().decode(DailyContentManifest.self, from: Data(contentsOf: url))
        #expect(!manifest.cards.isEmpty)
        for card in manifest.cards + [DailyContentProvider.fallbackCard] {
            try autoreleasepool {
                let snapshot = DailyCardShareSnapshot(card: card)
                let layout = try DailyCardShareRenderer.layout(for: snapshot)
                let export = try DailyCardShareRenderer.render(snapshot)
                let cgImage = try #require(export.image.cgImage)
                #expect(cgImage.width == 1080)
                #expect(cgImage.height <= 2400)
                #expect(cgImage.height == Int(layout.size.height))
                #expect(export.image.scale == 1)
                #expect(layout.quote.minY > layout.artwork.maxY)
                #expect(layout.branding.maxY < layout.size.height)
                let required = ("“\(card.quote)”" as NSString).boundingRect(
                    with: CGSize(width: layout.quote.width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: DailyCardShareRenderer.attributes(font: DailyCardShareRenderer.quoteFont, color: .white),
                    context: nil)
                #expect(layout.quote.height >= ceil(required.height))
                if let vibe = layout.vibe { #expect(vibe.maxY < layout.branding.minY) }
                #expect(export.text == snapshot.companionText)
            }
        }
    }

    @Test("Fresh PNG contains only encoding metadata, without location or private source fields")
    func metadata() throws {
        let export = try DailyCardShareRenderer.render(DailyCardShareSnapshot(card: card()))
        let data = try #require(export.image.pngData())
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        // UIKit adds geometry/color fields even to a fresh bitmap. Permit only
        // these encoding facts, never source identity, timestamps, or location.
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        #expect(Set(exif.keys).isSubset(of: [
            kCGImagePropertyExifColorSpace as String,
            kCGImagePropertyExifPixelXDimension as String,
            kCGImagePropertyExifPixelYDimension as String
        ]))
        #expect(properties[kCGImagePropertyGPSDictionary as String] == nil)
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        #expect(Set(tiff.keys).isSubset(of: [
            kCGImagePropertyTIFFOrientation as String,
            kCGImagePropertyTIFFResolutionUnit as String,
            kCGImagePropertyTIFFXResolution as String,
            kCGImagePropertyTIFFYResolution as String
        ]))
        let png = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any]
        #expect(png?[kCGImagePropertyPNGDescription as String] == nil)
        #expect(png?[kCGImagePropertyPNGAuthor as String] == nil)
        #expect(png?[kCGImagePropertyPNGCreationTime as String] == nil)
    }

    @Test("Native share preview retains the image payload and never requests a remote URL")
    func previewMetadata() throws {
        let export = try DailyCardShareRenderer.render(DailyCardShareSnapshot(card: card()))
        let source = DailyCardShareImageSource(image: export.image)
        let controller = UIActivityViewController(activityItems: [source, export.text], applicationActivities: nil)
        #expect(source.activityViewControllerPlaceholderItem(controller) as? UIImage === export.image)
        #expect(source.activityViewController(controller, itemForActivityType: nil) as? UIImage === export.image)
        #expect(source.activityViewController(controller, itemForActivityType: .saveToCameraRoll) as? UIImage === export.image)
        let metadata = try #require(source.activityViewControllerLinkMetadata(controller))
        #expect(metadata.title == "Daily Whiskers")
        #expect(metadata.url == nil)
        #expect(metadata.originalURL == nil)
        #expect(metadata.imageProvider?.hasItemConformingToTypeIdentifier("public.image") == true)
    }

    @Test("Missing art and oversized future content fail without a misleading partial export")
    func failures() {
        #expect(throws: DailyCardShareError.self) {
            try DailyCardShareRenderer.render(DailyCardShareSnapshot(card: card(image: "missing-share-artwork")))
        }
        #expect(throws: DailyCardShareError.self) {
            try DailyCardShareRenderer.render(DailyCardShareSnapshot(card: card(quote: String(repeating: "Long quote. ", count: 250))))
        }
        #expect(throws: DailyCardShareError.self) {
            try DailyCardShareRenderer.layout(for: DailyCardShareSnapshot(card: card(quote: String(repeating: "x", count: 5000))))
        }
    }

    @Test("Render failure clears progress and retry preserves the original snapshot")
    func retry() async {
        var attempts = 0
        let share = DailyCardShareState { snapshot in
            attempts += 1
            if attempts == 1 { throw DailyCardShareError.missingArtwork }
            return DailyCardShareExport(image: UIImage(), text: snapshot.companionText)
        }
        await share.start(card: card(quote: "Original"))
        #expect(share.hasError)
        #expect(!share.isRendering)
        #expect(share.export == nil)
        await share.retry()
        #expect(attempts == 2)
        #expect(!share.hasError)
        #expect(!share.isRendering)
        #expect(share.export?.text.contains("Original") == true)
    }

    @Test("Duplicate taps do not replace a pending or presented card; cancellation permits a fresh share")
    func duplicateAndCancellation() async {
        var attempts = 0
        let share = DailyCardShareState { snapshot in
            attempts += 1
            return DailyCardShareExport(image: UIImage(), text: snapshot.companionText)
        }
        let first = Task { await share.start(card: card(quote: "First")) }
        // start() yields with its lock held before rendering.
        while !share.isRendering && share.export == nil { await Task.yield() }
        await share.start(card: card(quote: "Duplicate"))
        await first.value
        #expect(attempts == 1)
        #expect(share.export?.text.contains("First") == true)
        await share.start(card: card(quote: "Presented duplicate"))
        #expect(attempts == 1)
        share.sheetDismissed()
        #expect(share.export == nil)
        #expect(share.snapshot == nil)
        await share.start(card: card(quote: "New card"))
        #expect(attempts == 2)
        #expect(share.export?.text.contains("New card") == true)
    }

    @Test("Activity failure retains snapshot for retry; success releases it")
    func activityCompletion() async {
        let share = DailyCardShareState { DailyCardShareExport(image: UIImage(), text: $0.companionText) }
        await share.start(card: card())
        share.completeActivity(failed: true)
        #expect(share.export == nil)
        #expect(!share.hasError)
        share.sheetDismissed()
        #expect(share.hasError)
        #expect(share.snapshot != nil)
        await share.retry()
        #expect(share.export != nil)
        share.completeActivity(failed: false)
        share.sheetDismissed()
        #expect(!share.hasError)
        #expect(share.export == nil)
        #expect(share.snapshot == nil)
    }
}

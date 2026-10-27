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

    @Test("Retained content survives navigation, content replacement and activity retry with identical pixels")
    func retainedVersionThroughRetry() async throws {
        let original = card(quote: "The original full quote.")
        let retained = try CardSnapshot.capture(card: original, artwork: BundledCardArtwork.bytes(for: original))
        let expected = try DailyCardShareRenderer.render(DailyCardShareSnapshot(retained: retained))
        let share = DailyCardShareState()
        let render = Task { await share.start(retained: retained) }
        while !share.isRendering && share.export == nil { await Task.yield() }
        // Simulate a new screen/manifest version arriving while rendering is suspended.
        let replacement = DailyCard(id: original.id, archetype: "forest", imageName: original.imageName,
                                    quote: "A replacement must not leak into sharing.", vibe: "New")
        await share.start(card: replacement)
        await render.value
        #expect(share.snapshot?.archetype == retained.snapshot.archetype)
        #expect(share.snapshot?.retainedArtwork == retained.artwork)
        #expect(share.export?.image.pngData() == expected.image.pngData())
        share.completeActivity(failed: true)
        share.sheetDismissed()
        await share.retry()
        #expect(share.export?.image.pngData() == expected.image.pngData())
        #expect(share.export?.text == expected.text)
        share.finish()
        #expect(share.snapshot == nil)
    }

    @Test("Approved logo becomes white on transparent pixels without the colored tile")
    func monochromeWatermark() throws {
        let url = try #require(Bundle.main.url(forResource: DailyCardShareRenderer.logoResource, withExtension: "png"))
        #expect(try ArtworkIdentity.pixelDigest(Data(contentsOf: url)) == "b3d7af74e7ccbf20228ad2d0d07d249ba375f58fcd8bf6500a759108f80d8931")
        let image = try #require(DailyCardShareRenderer.watermark?.cgImage)
        #expect(image.width == 681 && image.height == 681)
        var pixels = [UInt8](repeating: 0, count: 681 * 681 * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: 681, height: 681,
                bitsPerComponent: 8, bytesPerRow: 681 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 681, height: 681))
        }
        let offsets = stride(from: 0, to: pixels.count, by: 4)
        #expect(offsets.allSatisfy { pixels[$0] == pixels[$0 + 1] && pixels[$0] == pixels[$0 + 2] && pixels[$0] == pixels[$0 + 3] })
        #expect(offsets.filter { pixels[$0 + 3] > 0 }.count > 100_000)
        for y in [0, 680] {
            #expect((0..<681).allSatisfy { pixels[(y * 681 + $0) * 4 + 3] == 0 })
        }
        for x in [0, 680] {
            #expect((0..<681).allSatisfy { pixels[($0 * 681 + x) * 4 + 3] == 0 })
        }
    }

    @Test("Export preserves the upright artwork pixels above the quote")
    func uprightArtwork() throws {
        let input = card()
        let artwork = try #require(BundledCardArtwork.image(named: input.imageName))
        let export = try DailyCardShareRenderer.render(DailyCardShareSnapshot(card: input))
        let artSize = CGSize(width: 972, height: 972 * artwork.size.height / artwork.size.width)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let reference = UIGraphicsImageRenderer(size: artSize, format: format).image { _ in
            artwork.draw(in: CGRect(origin: .zero, size: artSize))
        }
        let inset = CGRect(origin: .zero, size: artSize).insetBy(dx: 50, dy: 50)
        let expected = try #require(reference.cgImage?.cropping(to: inset))
        let actual = try #require(export.image.cgImage?.cropping(to: inset.offsetBy(dx: 54, dy: 54)))
        func samples(_ image: CGImage) throws -> [UInt8] {
            var pixels = [UInt8](repeating: 0, count: 8 * 12 * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(data: buffer.baseAddress, width: 8, height: 12,
                    bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 12))
            }
            return pixels
        }
        let differences = zip(try samples(expected), try samples(actual)).map { abs(Int($0) - Int($1)) }
        #expect(Double(differences.reduce(0, +)) / Double(differences.count) < 5)
    }

    @Test("Long quotes grow the shared card without shrinking the artwork")
    func longQuote() throws {
        let short = try DailyCardShareRenderer.render(DailyCardShareSnapshot(card: card()))
        let long = try DailyCardShareRenderer.render(DailyCardShareSnapshot(card: card(quote:
            "Take a gentle breath. Let the quiet settle around you. There is room for every small beginning, every brave pause, and every kind thought you offer yourself today.")))
        #expect(long.image.size.height > short.image.size.height)
        #expect(long.image.size.height <= DailyCardShareRenderer.maximumHeight)
        let region = CGRect(x: 150, y: 150, width: 780, height: 1200)
        let shortArt = try #require(short.image.cgImage?.cropping(to: region))
        let longArt = try #require(long.image.cgImage?.cropping(to: region))
        #expect(try ArtworkIdentity.pixelDigest(shortArt) == ArtworkIdentity.pixelDigest(longArt))
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
                let export = try DailyCardShareRenderer.render(snapshot)
                let retained = try CardSnapshot.capture(card: card, artwork: BundledCardArtwork.bytes(for: card))
                let savedExport = try DailyCardShareRenderer.render(DailyCardShareSnapshot(retained: retained))
                #expect(export.image.pngData() == savedExport.image.pngData())
                #expect(export.text == savedExport.text)
                let cgImage = try #require(export.image.cgImage)
                #expect(cgImage.width == 1080)
                #expect(cgImage.height <= 2400)
                #expect(export.image.scale == 1)
                #expect(cgImage.height > 1600)
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
            try DailyCardShareRenderer.render(DailyCardShareSnapshot(card: card(quote: String(repeating: "x", count: 5000))))
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

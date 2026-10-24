import XCTest
import SwiftUI
@testable import DailyWhiskers

@MainActor
final class DailyCardShareVisualTests: XCTestCase {
    func testMonochromeLogoForVisualReview() throws {
        let image = try XCTUnwrap(DailyCardShareRenderer.watermark)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Monochrome-approved-logo-transparent"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRepresentativeThemesForVisualReview() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "daily_whiskers_content", withExtension: "json"))
        let manifest = try JSONDecoder().decode(DailyContentManifest.self, from: Data(contentsOf: url))
        for archetype in ["arcane", "forest", "alchemy", "noble", "celestial", "cozy"] {
            let card = try XCTUnwrap(manifest.cards.first { $0.archetype == archetype })
            let export = try DailyCardShareRenderer.render(DailyCardShareSnapshot(card: card))
            let attachment = XCTAttachment(image: export.image)
            attachment.name = "Export-" + archetype
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testLongestBundledQuoteExportForVisualReview() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "daily_whiskers_content", withExtension: "json"))
        let manifest = try JSONDecoder().decode(DailyContentManifest.self, from: Data(contentsOf: url))
        let longest = try XCTUnwrap(manifest.cards.max { $0.quote.count < $1.quote.count })
        let export = try DailyCardShareRenderer.render(DailyCardShareSnapshot(card: longest))
        XCTAssertEqual(export.image.size.width, 1080)
        XCTAssertLessThanOrEqual(export.image.size.height, 2400)
        let attachment = XCTAttachment(image: export.image)
        attachment.name = "Longest bundled quote — local share export"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testAdaptiveViewportRetainsArtworkScaleAndNaturalScrollingHeight() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "daily_whiskers_content", withExtension: "json"))
        let cards = try JSONDecoder().decode(DailyContentManifest.self, from: Data(contentsOf: url)).cards
        let extremes = [try XCTUnwrap(cards.min { $0.quote.count < $1.quote.count }),
                        try XCTUnwrap(cards.max { $0.quote.count < $1.quote.count })]
        for (index, card) in extremes.enumerated() {
            let artwork = try XCTUnwrap(BundledCardArtwork.image(named: card.imageName))
            let data = DailyCardData(archetype: card.archetype, imageName: card.imageName, quote: card.quote, vibe: card.vibe ?? "")
            func render(_ size: CGSize, text: DynamicTypeSize = .large) throws -> UIImage {
                let renderer = ImageRenderer(content:
                    AdaptiveRitualCardPresentation(data: data, artwork: artwork, viewport: size,
                                                   compact: false, tightQuotePanel: true)
                        .environment(\.dynamicTypeSize, text).environment(\.colorScheme, .dark))
                renderer.scale = 1
                return try XCTUnwrap(renderer.uiImage)
            }
            let portrait = try render(CGSize(width: 988, height: 1200))
            let wide = try render(CGSize(width: 1332, height: 870))
            let narrow = try render(CGSize(width: 600, height: 600))
            let shortWindow = try render(CGSize(width: 1332, height: 500))
            let accessibility = try render(CGSize(width: 1332, height: 870), text: .accessibility5)
            XCTAssertEqual(portrait.size.width, 520, accuracy: 1)
            XCTAssertEqual(wide.size.width, 960, accuracy: 1)
            XCTAssertEqual(wide.size.height, 780, accuracy: 1)
            for fallback in [narrow, shortWindow, accessibility] {
                XCTAssertEqual(fallback.size.width, 520, accuracy: 1)
                XCTAssertGreaterThan(fallback.size.height, 870)
            }
            // Compare actual artwork pixels at the same scale, excluding frame/gradient.
            // A smaller image, crop, or new side gutters changes these samples and fails.
            let crop = CGRect(x: 40, y: 40, width: 440, height: 640)
            func samples(_ image: UIImage) throws -> [UInt8] {
                let cropped = try XCTUnwrap(image.cgImage?.cropping(to: crop))
                var pixels = [UInt8](repeating: 0, count: 8 * 12 * 4)
                try pixels.withUnsafeMutableBytes { bytes in
                    let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 8, height: 12,
                        bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    context.interpolationQuality = .high
                    context.draw(cropped, in: CGRect(x: 0, y: 0, width: 8, height: 12))
                }
                return pixels
            }
            let reference = try samples(portrait)
            for image in [wide, narrow, shortWindow, accessibility] {
                let differences = zip(reference, try samples(image)).map { abs(Int($0) - Int($1)) }
                XCTAssertLessThan(Double(differences.reduce(0, +)) / Double(differences.count), 2)
            }
            for (name, image) in [("portrait", portrait), ("wide", wide), ("narrow-scroll", narrow),
                                  ("short-scroll", shortWindow), ("accessibility-scroll", accessibility)] {
                let attachment = XCTAttachment(image: image)
                attachment.name = "Adaptive-\(index)-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }

}

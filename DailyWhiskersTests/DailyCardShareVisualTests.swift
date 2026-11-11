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
            let fixture = "\(index == 0 ? "shortest" : "longest") quote / \(card.imageName)"
            let artwork = try XCTUnwrap(BundledCardArtwork.image(named: card.imageName))
            let data = DailyCardData(archetype: card.archetype, imageName: card.imageName, quote: card.quote, vibe: card.vibe ?? "")
            func render(_ name: String, _ size: CGSize, text: DynamicTypeSize = .large) throws -> UIImage {
                let renderer = ImageRenderer(content:
                    AdaptiveRitualCardPresentation(data: data, artwork: artwork, viewport: size,
                                                   compact: false, tightQuotePanel: true)
                        .environment(\.dynamicTypeSize, text).environment(\.colorScheme, .dark))
                renderer.scale = 1
                var image: Result<UIImage, Error>?
                // Draw synchronously into an owned 1x sRGB bitmap before cropping.
                // Sampling renderer.uiImage can otherwise read a deferred image provider.
                renderer.render(rasterizationScale: 1) { size, draw in
                    image = Result {
                        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
                        let context = try XCTUnwrap(CGContext(data: nil,
                            width: Int(ceil(size.width)), height: Int(ceil(size.height)),
                            bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                | CGBitmapInfo.byteOrder32Big.rawValue),
                            "\(fixture) / \(name): could not allocate render bitmap")
                        // A bitmap CGContext already uses the drawing closure's bottom-left origin.
                        draw(context)
                        let raster = try XCTUnwrap(context.makeImage(),
                            "\(fixture) / \(name): could not materialize rendered image")
                        return UIImage(cgImage: raster, scale: 1, orientation: .up)
                    }
                }
                return try XCTUnwrap(image, "\(fixture) / \(name): renderer did not draw").get()
            }
            let portrait = try render("portrait", CGSize(width: 988, height: 1200))
            let wide = try render("wide", CGSize(width: 1332, height: 870))
            let narrow = try render("narrow-scroll", CGSize(width: 600, height: 600))
            let shortWindow = try render("short-scroll", CGSize(width: 1332, height: 500))
            let accessibility = try render("accessibility-scroll", CGSize(width: 1332, height: 870), text: .accessibility5)
            XCTAssertEqual(portrait.size.width, 520, accuracy: 1, "\(fixture) / portrait")
            XCTAssertEqual(wide.size.width, 960, accuracy: 1, "\(fixture) / wide")
            XCTAssertEqual(wide.size.height, 780, accuracy: 1, "\(fixture) / wide")
            for (name, fallback) in [("narrow-scroll", narrow), ("short-scroll", shortWindow),
                                     ("accessibility-scroll", accessibility)] {
                XCTAssertEqual(fallback.size.width, 520, accuracy: 1, "\(fixture) / \(name)")
                XCTAssertGreaterThan(fallback.size.height, 870, "\(fixture) / \(name)")
            }
            // Compare actual artwork pixels at the same scale, excluding frame/gradient.
            // A smaller image, crop, or new side gutters changes these samples and fails.
            let crop = CGRect(x: 40, y: 40, width: 440, height: 640)
            func samples(_ image: UIImage, name: String) throws -> [UInt8] {
                let cropped = try XCTUnwrap(image.cgImage?.cropping(to: crop),
                    "\(fixture) / \(name): could not crop artwork")
                var pixels = [UInt8](repeating: 0, count: 8 * 12 * 4)
                try pixels.withUnsafeMutableBytes { bytes in
                    let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 8, height: 12,
                        bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                            | CGBitmapInfo.byteOrder32Big.rawValue),
                        "\(fixture) / \(name): could not allocate sampling bitmap")
                    context.interpolationQuality = .high
                    context.draw(cropped, in: CGRect(x: 0, y: 0, width: 8, height: 12))
                }
                let nonOpaqueSamples = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] != 255 }.count
                XCTAssertEqual(nonOpaqueSamples, 0,
                    "\(fixture) / \(name): artwork samples must be opaque; empty or incomplete rasterization")
                return pixels
            }
            let reference = try samples(portrait, name: "portrait")
            for (name, image) in [("wide", wide), ("narrow-scroll", narrow),
                                   ("short-scroll", shortWindow), ("accessibility-scroll", accessibility)] {
                let differences = zip(reference, try samples(image, name: name)).map { abs(Int($0) - Int($1)) }
                XCTAssertLessThan(Double(differences.reduce(0, +)) / Double(differences.count), 2,
                    "\(fixture) / \(name): artwork differs from portrait")
            }
            for (name, image) in [("portrait", portrait), ("wide", wide), ("narrow-scroll", narrow),
                                  ("short-scroll", shortWindow), ("accessibility-scroll", accessibility)] {
                let attachment = XCTAttachment(image: image)
                attachment.name = "Adaptive-\(index)-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }

}

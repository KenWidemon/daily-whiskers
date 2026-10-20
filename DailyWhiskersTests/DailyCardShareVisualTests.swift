import XCTest
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
}

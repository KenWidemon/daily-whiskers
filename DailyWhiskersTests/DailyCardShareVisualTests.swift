import XCTest
@testable import DailyWhiskers

@MainActor
final class DailyCardShareVisualTests: XCTestCase {
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

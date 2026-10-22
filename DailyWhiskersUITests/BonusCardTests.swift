import XCTest
import UIKit

final class BonusCardTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ci-smoke", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ci-smoke-offline"].waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws {
        capture("Final state including any unexpected behavior")
        app.terminate()
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func waitEnabled(_ button: XCUIElement) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)], timeout: 15), .completed)
    }
    private func openBonus() {
        let menu = app.buttons["card-menu"]
        waitEnabled(menu); menu.tap()
        app.buttons["Open Bonus Card"].tap()
        XCTAssertTrue(element("bonus-card-quote").waitForExistence(timeout: 15))
    }
    private func today() {
        app.buttons["card-menu"].tap(); app.buttons["Return to Today"].tap()
        XCTAssertTrue(element("daily-card-quote").waitForExistence(timeout: 10))
    }
    private func saved(_ value: String) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: app.buttons["save-daily-card"])], timeout: 10), .completed)
    }
    func testOfflineBonusPersistenceTodayFavoritesShareAndMatchedPreviews() {
        let originalQuote = element("daily-card-quote")
        XCTAssertTrue(originalQuote.waitForExistence(timeout: 10))
        let original = originalQuote.label
        capture("01 Today portrait")
        openBonus()
        let quote = element("bonus-card-quote").label
        XCTAssertNotEqual(quote, original)
        let bounds = app.windows.firstMatch.frame
        XCTAssertTrue(bounds.contains(element("bonus-card-quote").frame))
        XCTAssertTrue(element("bonus-card-vibe").isHittable)
        assertMenuFits()
        let bonusBounds = ["frame", "quote", "vibe"].map { element("bonus-card-" + $0).frame }
        capture("02 Bonus portrait")
        let save = app.buttons["save-daily-card"]
        if save.value as? String == "Saved" { save.tap(); saved("Not saved") }
        XCTAssertEqual(save.label, "Save Card")
        save.tap(); saved("Saved")
        XCTAssertEqual(save.label, "Remove from Saved Cards")
        XCTAssertEqual(bonusBounds, ["frame", "quote", "vibe"].map { element("bonus-card-" + $0).frame })
        capture("03 Bonus saved unchanged geometry")
        var landscapeBonusBounds: [CGRect] = []
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            assertTabletCardFits(prefix: "bonus-card")
            landscapeBonusBounds = ["frame", "quote", "vibe"].map { element("bonus-card-" + $0).frame }
            capture("iPad Bonus complete landscape")
            XCUIDevice.shared.orientation = .portrait
        }
        today(); XCTAssertEqual(element("daily-card-quote").label, original)
        openBonus(); XCTAssertEqual(element("bonus-card-quote").label, quote)
        app.terminate(); app.launch()
        XCTAssertTrue(element("daily-card-quote").waitForExistence(timeout: 15))
        openBonus(); XCTAssertEqual(element("bonus-card-quote").label, quote); saved("Saved")
        app.buttons["open-saved-cards"].tap()
        let row = app.buttons.matching(identifier: "saved-card-row").matching(NSPredicate(format: "label == %@", quote)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(element("saved-card-quote").waitForExistence(timeout: 10))
        XCTAssertEqual(element("saved-card-quote").label, quote)
        for (index, part) in ["frame", "quote", "vibe"].enumerated() {
            let savedBounds = element("saved-card-" + part).frame, bonus = bonusBounds[index]
            XCTAssertEqual(savedBounds.minX, bonus.minX, accuracy: 1)
            XCTAssertEqual(savedBounds.minY, bonus.minY, accuracy: 1)
            XCTAssertEqual(savedBounds.width, bonus.width, accuracy: 1)
            XCTAssertEqual(savedBounds.height, bonus.height, accuracy: 1)
        }
        capture("04 Exact saved bonus")
        if !landscapeBonusBounds.isEmpty {
            XCUIDevice.shared.orientation = .landscapeLeft
            assertTabletCardFits(prefix: "saved-card")
            XCTAssertEqual(landscapeBonusBounds, ["frame", "quote", "vibe"].map { element("saved-card-" + $0).frame })
            capture("iPad saved Bonus complete landscape")
            XCUIDevice.shared.orientation = .portrait
        }
        app.terminate(); app.launch(); openBonus()
        app.buttons["Share Bonus Card"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 15))
        capture("05 Bonus existing share sheet")
        let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: UIDevice.current.userInterfaceIdiom == .pad ? 0.5 : 0.25))
        XCTAssertFalse(sheet.frame.contains(outside.screenPoint)); outside.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sheet)], timeout: 10), .completed)
        save.tap(); saved("Not saved")
        XCTAssertEqual(save.label, "Save Card")
        today(); XCTAssertEqual(element("daily-card-quote").label, original)
    }
    private func assertTabletCardFits(prefix: String) {
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.windows.firstMatch.frame.width > self.app.windows.firstMatch.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        let bounds = element(prefix + "-frame").frame
        XCTAssertGreaterThanOrEqual(bounds.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(bounds.maxY, app.staticTexts["ci-smoke-offline"].frame.minY)
        XCTAssertTrue(element(prefix + "-vibe").isHittable)
    }

    func testRetainedBonusOpensSavesAndSharesWhenTodayArtworkIsUnavailable() {
        openBonus()
        let quote = element("bonus-card-quote").label
        let bounds = ["frame", "quote", "vibe"].map { element("bonus-card-" + $0).frame }
        let save = app.buttons["save-daily-card"]
        if save.value as? String == "Saved" { save.tap(); saved("Not saved") }
        app.terminate()
        app.launchArguments.append("--ci-smoke-today-artwork-unavailable")
        app.launch()
        let failure = app.alerts["Couldn't Prepare Card"]
        XCTAssertTrue(failure.waitForExistence(timeout: 15))
        capture("09 Injected Today artwork failure")
        failure.buttons["Cancel"].tap()
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(app.buttons["share-daily-card"].isEnabled)
        openBonus()
        XCTAssertEqual(element("bonus-card-quote").label, quote)
        XCTAssertEqual(bounds, ["frame", "quote", "vibe"].map { element("bonus-card-" + $0).frame })
        capture("10 Retained bonus despite unavailable Today artwork")
        save.tap(); saved("Saved")
        app.buttons["Share Bonus Card"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 15))
        capture("11 Retained bonus share despite unavailable Today artwork")
        let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: UIDevice.current.userInterfaceIdiom == .pad ? 0.5 : 0.25))
        XCTAssertFalse(sheet.frame.contains(outside.screenPoint)); outside.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sheet)], timeout: 10), .completed)
        today()
        XCTAssertFalse(save.isEnabled)
        openBonus(); XCTAssertEqual(element("bonus-card-quote").label, quote); saved("Saved")
        save.tap(); saved("Not saved")
    }

    func testLargestTextBonusNavigationAndLandscapeReachability() {
        app.terminate()
        app.launchArguments = ["--ci-smoke", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); openBonus()
        capture("06 Bonus largest text portrait top")
        assertMenuFits()
        captureScrollableQuote(name: "07 Bonus largest text portrait")
        XCTAssertTrue(app.buttons["save-daily-card"].isHittable)
        XCTAssertTrue(app.buttons["Share Bonus Card"].isHittable)
        capture("07 Bonus largest text portrait quote")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.windows.firstMatch.frame.width > self.app.windows.firstMatch.frame.height
        }, object: nil)], timeout: 10), .completed)
        assertMenuFits()
        captureScrollableQuote(name: "08 Bonus largest text landscape")
        XCTAssertTrue(app.buttons["card-menu"].isHittable)
        capture("08 Bonus largest text landscape")
        today()
        XCUIDevice.shared.orientation = .portrait
    }
    private func assertMenuFits() {
        let menu = app.buttons["card-menu"].frame
        XCTAssertGreaterThanOrEqual(menu.minX, app.buttons["open-saved-cards"].frame.maxX)
        XCTAssertLessThanOrEqual(menu.maxX, app.buttons["save-daily-card"].frame.minX)
        XCTAssertTrue(app.buttons["card-menu"].isHittable)
    }

    // Verify both boundaries of long quotes through scrolling at their requested size.
    private func captureScrollableQuote(name: String) {
        let quote = element("bonus-card-quote"), vibe = element("bonus-card-vibe")
        let window = app.windows.firstMatch.frame
        let top = app.navigationBars.firstMatch.frame.maxY + 8
        let bottom = app.staticTexts["ci-smoke-offline"].frame.minY - 4
        func drag(_ delta: CGFloat) {
            let distance = min(abs(delta), bottom - top - 40)
            let startY = delta > 0 ? bottom - 20 : top + 20
            let endY = startY + (delta > 0 ? -distance : distance)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: window.midX, dy: startY))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: window.midX, dy: endY)),
                       withVelocity: .slow, thenHoldForDuration: 0.25)
        }
        for _ in 0..<12 where abs(quote.frame.minY - (top + 8)) > 12 {
            let previous = quote.frame.minY
            drag(previous - (top + 8))
            if abs(quote.frame.minY - previous) < 1 { break }
        }
        XCTAssertGreaterThanOrEqual(quote.frame.minY, top - 4)
        XCTAssertLessThan(quote.frame.minY, bottom - 40)
        capture(name + "-Quote-Start")
        for _ in 0..<12 where vibe.frame.maxY > bottom || vibe.frame.minY < top {
            drag(max(32, vibe.frame.maxY - (bottom - 4)))
        }
        XCTAssertGreaterThan(quote.frame.maxY, top + 40)
        XCTAssertLessThanOrEqual(quote.frame.maxY, bottom)
        XCTAssertGreaterThanOrEqual(vibe.frame.minY, top)
        XCTAssertLessThanOrEqual(vibe.frame.maxY, bottom)
        XCTAssertTrue(vibe.isHittable)
        capture(name + "-Quote")
    }

}

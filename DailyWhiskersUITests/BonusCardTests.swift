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
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: app.buttons["daily-card-options"])], timeout: 10), .completed)
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
        let save = app.buttons["daily-card-options"]
        if save.value as? String == "Saved" { app.toggleDailyCardSave(); saved("Not saved") }
        app.assertDailySaveActionLabel("Save Card")
        app.toggleDailyCardSave(); saved("Saved")
        app.assertDailySaveActionLabel("Remove from Saved Cards")
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
        app.openCardOptions(); app.buttons["Share Bonus Card"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 15))
        capture("05 Bonus existing share sheet")
        let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: UIDevice.current.userInterfaceIdiom == .pad ? 0.5 : 0.25))
        XCTAssertFalse(sheet.frame.contains(outside.screenPoint)); outside.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sheet)], timeout: 10), .completed)
        app.toggleDailyCardSave(); saved("Not saved")
        app.assertDailySaveActionLabel("Save Card")
        today(); XCTAssertEqual(element("daily-card-quote").label, original)
    }
    func testCardOptionsReviewScreens() {
        for (orientation, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            app.terminate()
            XCUIDevice.shared.orientation = orientation
            app.launch()
            XCTAssertTrue(element("daily-card-quote").waitForExistence(timeout: 15))
            let oriented = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let frame = self.app.windows.firstMatch.frame
                return orientation == .portrait ? frame.height > frame.width : frame.width > frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [oriented], timeout: 10), .completed)
            let original = element("daily-card-quote").label
            if app.buttons["daily-card-options"].value as? String == "Saved" {
                app.toggleDailyCardSave(); saved("Not saved")
            }
            reviewOptions("Today-" + name, shareLabel: "Share Today's Card", saveLabel: "Save Card")
            app.toggleDailyCardSave(); saved("Saved")
            openBonus()
            if app.buttons["daily-card-options"].value as? String == "Saved" {
                app.toggleDailyCardSave(); saved("Not saved")
            }
            reviewOptions("Bonus-" + name, shareLabel: "Share Bonus Card", saveLabel: "Save Card")
            today()
            app.buttons["open-saved-cards"].tap()
            let row = app.buttons.matching(identifier: "saved-card-row").matching(NSPredicate(format: "label == %@", original)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            for _ in 0..<4 where !row.isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(row.isHittable); row.tap()
            XCTAssertTrue(element("saved-card-quote").waitForExistence(timeout: 10))
            XCTAssertEqual(element("saved-card-quote").label, original)
            reviewOptions("Saved-" + name, shareLabel: "Share Saved Card", saveLabel: "Remove from Saved Cards")
        }
    }

    private func reviewOptions(_ name: String, shareLabel: String, saveLabel: String) {
        capture("Review-" + name + "-closed")
        app.openCardOptions()
        XCTAssertTrue(app.buttons[shareLabel].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[shareLabel].isHittable)
        XCTAssertTrue(app.buttons[saveLabel].isHittable)
        capture("Review-" + name + "-open")
        app.dismissCardOptions()
    }

    func testTodayOptionsTouchTarget() { checkDailyOptionsTouchTarget(bonus: false, largest: false) }
    func testBonusOptionsTouchTarget() { checkDailyOptionsTouchTarget(bonus: true, largest: false) }
    func testLargestTextTodayOptionsTouchTarget() { checkDailyOptionsTouchTarget(bonus: false, largest: true) }
    func testLargestTextBonusOptionsTouchTarget() { checkDailyOptionsTouchTarget(bonus: true, largest: true) }

    private func checkDailyOptionsTouchTarget(bonus: Bool, largest: Bool) {
        if largest {
            app.terminate()
            app.launchArguments = ["--ci-smoke", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            XCTAssertTrue(app.staticTexts["ci-smoke-offline"].waitForExistence(timeout: 15))
        }
        if bonus { openBonus() }
        let options = app.buttons["daily-card-options"]
        waitEnabled(options)
        XCTAssertEqual(options.label, bonus ? "Bonus Card Options" : "Today's Card Options")
        let bounds = options.frame, state = options.value as? String
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let edge: CGFloat = 21.5
        let samples: [(String, CGFloat, CGFloat)] = [
            ("center", 0, 0), ("top", 0, -edge), ("bottom", 0, edge),
            ("left", -edge, 0), ("right", edge, 0),
            ("top-left", -edge, -edge), ("top-right", edge, -edge),
            ("bottom-left", -edge, edge), ("bottom-right", edge, edge),
            ("center-after-edges", 0, 0)
        ]
        let name = (bonus ? "Bonus" : "Today") + (largest ? "-AX5" : "-Large")
        capture(name + "-coordinate-start")
        for (sample, dx, dy) in samples {
            XCTAssertEqual(options.frame, bounds)
            let point = CGPoint(x: bounds.midX + dx, y: bounds.midY + dy)
            let anchor = origin.screenPoint
            origin.withOffset(CGVector(dx: point.x - anchor.x, dy: point.y - anchor.y)).tap()
            let opened = app.buttons["save-daily-card"].waitForExistence(timeout: 5)
            let data = try! JSONSerialization.data(withJSONObject: [
                "sample": sample, "x": point.x, "y": point.y, "opened": opened,
                "axFrame": [bounds.minX, bounds.minY, bounds.width, bounds.height]
            ])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = name + " coordinate " + sample
            attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertTrue(opened, "Options did not open at \(sample) of the 44-point target: \(point)")
            XCTAssertTrue(app.buttons["share-daily-card"].isHittable)
            XCTAssertEqual(app.buttons["save-daily-card"].label, state == "Saved" ? "Remove from Saved Cards" : "Save Card")
            app.dismissCardOptions()
            XCTAssertEqual(options.value as? String, state)
        }
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
        let save = app.buttons["daily-card-options"]
        if save.value as? String == "Saved" { app.toggleDailyCardSave(); saved("Not saved") }
        app.terminate()
        app.launchArguments.append("--ci-smoke-today-artwork-unavailable")
        app.launch()
        let failure = app.alerts["Couldn't Prepare Card"]
        XCTAssertTrue(failure.waitForExistence(timeout: 15))
        capture("09 Injected Today artwork failure")
        failure.buttons["Cancel"].tap()
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(app.buttons["daily-card-options"].isEnabled) // Both actions are unavailable with no snapshot.
        openBonus()
        XCTAssertEqual(element("bonus-card-quote").label, quote)
        XCTAssertEqual(bounds, ["frame", "quote", "vibe"].map { element("bonus-card-" + $0).frame })
        capture("10 Retained bonus despite unavailable Today artwork")
        app.toggleDailyCardSave(); saved("Saved")
        app.openCardOptions(); app.buttons["Share Bonus Card"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 15))
        capture("11 Retained bonus share despite unavailable Today artwork")
        let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: UIDevice.current.userInterfaceIdiom == .pad ? 0.5 : 0.25))
        XCTAssertFalse(sheet.frame.contains(outside.screenPoint)); outside.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sheet)], timeout: 10), .completed)
        today()
        XCTAssertFalse(save.isEnabled)
        openBonus(); XCTAssertEqual(element("bonus-card-quote").label, quote); saved("Saved")
        app.toggleDailyCardSave(); saved("Not saved")
    }

    func testLargestTextBonusNavigationAndLandscapeReachability() {
        app.terminate()
        app.launchArguments = ["--ci-smoke", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); openBonus()
        capture("06 Bonus largest text portrait top")
        assertMenuFits()
        captureScrollableQuote(name: "07 Bonus largest text portrait")
        XCTAssertTrue(app.buttons["daily-card-options"].isHittable)
        app.openCardOptions()
        XCTAssertTrue(app.buttons["Share Bonus Card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share Bonus Card"].isHittable)
        XCTAssertTrue(app.buttons["save-daily-card"].isHittable)
        app.dismissCardOptions()
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
        XCTAssertLessThanOrEqual(menu.maxX, app.buttons["daily-card-options"].frame.minX)
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

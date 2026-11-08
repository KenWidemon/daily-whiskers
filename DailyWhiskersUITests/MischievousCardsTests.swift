import XCTest
import UIKit

final class MischievousCardsTests: XCTestCase {
    private var app: XCUIApplication!
    private var restoreReduceMotion = false
    private let shadowQuote = "Today we conquer our enemies. After a nap."
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["DW_MISCHIEF_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["DW_STILLNESS_TEST_ID"] = UUID().uuidString
        app.launchArguments = ["--ci-smoke", "--ci-smoke-mischief-fixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ci-smoke-offline"].waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws {
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        capture("Final state")
        if restoreReduceMotion {
            let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
            settings.activate()
            settle()
            let toggle = settings.switches["Reduce Motion"]
            if toggle.waitForExistence(timeout: 5), toggle.value as? String == "1" { tapSystemSwitch(toggle) }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: toggle)], timeout: 5), .completed, "Restore actual system Reduce Motion Off")
        }
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func capture(_ title: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = title; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = title + " accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
    private func openSetting(_ label: String = "Mischievous Cards") {
        app.buttons["Settings"].tap()
        app.buttons[label].tap()
    }
    private func setToggle(_ id: String, _ on: Bool) {
        let toggle = app.switches[id]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: toggle)], timeout: 10), .completed)
        if (toggle.value as? String == "1") != on {
            let control = toggle.switches.firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            XCTAssertTrue(control.isHittable)
            control.tap()
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", on ? "1" : "0"), object: toggle)], timeout: 10), .completed)
    }
    private func openBonus() {
        app.buttons["card-menu"].tap(); app.buttons["Open Bonus Card"].tap()
        XCTAssertTrue(element("bonus-card-quote").waitForExistence(timeout: 15))
    }
    private func today() {
        app.buttons["card-menu"].tap(); app.buttons["Return to Today"].tap()
        XCTAssertTrue(element("daily-card-quote").waitForExistence(timeout: 10))
    }
    private func reachQuote() {
        let quote = element("bonus-card-quote")
        let scroll = app.scrollViews["bonus-card-content"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if quote.isHittable { return }
            scroll.swipeUp()
        }
        XCTAssertTrue(quote.isHittable, "The quote must be reachable in the shared scrolling presentation")
    }
    private func reachQuoteEnd() {
        let quote = element("bonus-card-quote")
        let scroll = app.scrollViews["bonus-card-content"]
        let top = max(scroll.frame.minY, app.navigationBars.firstMatch.frame.maxY + 8)
        let bottom = min(scroll.frame.maxY, app.staticTexts["ci-shadow-inactive"].frame.minY - 4)
        XCTAssertGreaterThanOrEqual(quote.frame.minY, top)
        XCTAssertLessThan(quote.frame.minY, bottom - 40, "Capture the beginning before scrolling to the end")
        for _ in 0..<8 {
            if quote.frame.maxY <= bottom { break }
            scroll.swipeUp()
        }
        XCTContext.runActivity(named: "Quote end: 4-point footer clearance") { activity in
            let quoteEnd = quote.frame.maxY
            let footerTop = app.staticTexts["ci-shadow-inactive"].frame.minY
            let evidence = XCTAttachment(string: "quoteEnd=\(quoteEnd); readableTop=\(top); bottomLimit=\(bottom); footerTop=\(footerTop); clearance=4")
            evidence.name = "Quote end measured bounds"
            evidence.lifetime = .keepAlways
            activity.add(evidence)
            XCTAssertTrue(quote.isHittable)
            XCTAssertGreaterThan(quoteEnd, top + 40)
            XCTAssertLessThanOrEqual(quoteEnd, bottom, "The end of the quote must be reachable above the fixture footer")
        }
    }

    private func reveal() {
        openSetting(); setToggle("mischief-toggle", true); app.buttons["Done"].tap(); openBonus()
        XCTAssertEqual(element("bonus-card-quote").label, shadowQuote)
    }

    func testDefaultOffOrdinaryBonusDoesNotUpgradeAfterOptIn() {
        openSetting()
        XCTAssertTrue(app.switches["mischief-toggle"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches["mischief-toggle"].value as? String, "0")
        capture("Default Off and help copy")
        app.buttons["Done"].tap()
        openBonus()
        let original = element("bonus-card-quote").label
        XCTAssertNotEqual(original, shadowQuote)
        openSetting(); setToggle("mischief-toggle", true); app.buttons["Done"].tap()
        today(); openBonus()
        XCTAssertEqual(element("bonus-card-quote").label, original)
        app.terminate(); app.launch(); openBonus()
        XCTAssertEqual(element("bonus-card-quote").label, original)
    }

    func testShadowRevealOptOutRelaunchSavingSharingAndToday() {
        let daily = element("daily-card-quote")
        XCTAssertTrue(daily.waitForExistence(timeout: 10))
        let original = daily.label
        reveal()
        XCTAssertTrue(app.windows.firstMatch.frame.contains(element("bonus-card-quote").frame))
        capture("Shadow Lord portrait")
        app.toggleDailyCardSave()
        openSetting(); setToggle("mischief-toggle", false); app.buttons["Done"].tap()
        XCTAssertEqual(element("bonus-card-quote").label, shadowQuote)
        today(); XCTAssertEqual(daily.label, original)
        openBonus(); XCTAssertEqual(element("bonus-card-quote").label, shadowQuote)
        app.terminate(); app.launch(); openBonus()
        XCTAssertEqual(element("bonus-card-quote").label, shadowQuote)
        XCTAssertEqual(app.buttons["daily-card-options"].value as? String, "Saved")
        app.buttons["open-saved-cards"].tap()
        let row = app.buttons.matching(identifier: "saved-card-row").matching(NSPredicate(format: "label == %@", shadowQuote)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(element("saved-card-quote").waitForExistence(timeout: 10))
        capture("Retained Shadow Lord after opt-out")
        app.terminate(); app.launch(); openBonus()
        app.openCardOptions(); app.buttons["Share Bonus Card"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 15))
        capture("Ordinary share sheet after opt-out")
    }

    private func tapSystemSwitch(_ row: XCUIElement) {
        let control = row.switches.firstMatch
        if control.exists { control.tap() } else { row.tap() }
    }

    private func settle(_ seconds: Double = 2) {
        let done = expectation(description: "Wait for native transitions")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 3)
    }
    private func cardPixels() -> Data {
        let image = XCUIScreen.main.screenshot().image.cgImage!
        let cropped = image.cropping(to: CGRect(x: 0, y: 240, width: image.width, height: image.height - 540))!
        return UIImage(cgImage: cropped).pngData()!
    }
    private func assertMotion(_ animated: Bool, _ title: String) {
        settle()
        let first = cardPixels()
        capture(title + " A")
        settle(3)
        let second = cardPixels()
        capture(title + " B")
        if animated { XCTAssertFalse(first == second, "Native card exterior should animate: " + title) }
        else { XCTAssertTrue(first == second, "Native card region should remain pixel-identical: " + title) }
    }

    func testNativeMotionStillnessAndActualSystemReduceMotion() {
        XCTAssertTrue(app.staticTexts["ci-stillness-system"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["ci-stillness-system"].label, "System Reduce Motion: Off")
        reveal()
        assertMotion(true, "Active wisps")
        openSetting("Stillness Mode"); setToggle("stillness-toggle", true); app.buttons["Done"].tap()
        assertMotion(false, "Stillness fixed wisps")
        openSetting("Stillness Mode"); setToggle("stillness-toggle", false); app.buttons["Done"].tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let accessibility = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Accessibility")).firstMatch
        for _ in 0..<8 where !accessibility.isHittable { settings.swipeUp() }
        XCTAssertTrue(accessibility.waitForExistence(timeout: 5)); accessibility.tap()
        let motion = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Motion")).firstMatch
        XCTAssertTrue(motion.waitForExistence(timeout: 5)); motion.tap()
        let toggle = settings.switches["Reduce Motion"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        restoreReduceMotion = true
        tapSystemSwitch(toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)], timeout: 5), .completed)
        app.activate()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "System Reduce Motion: On"), object: app.staticTexts["ci-stillness-system"])], timeout: 10), .completed)
        assertMotion(false, "Actual system Reduce Motion fixed wisps")
        settings.activate()
        settle()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        tapSystemSwitch(toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: toggle)], timeout: 5), .completed)
        restoreReduceMotion = false
        app.activate()
        assertMotion(true, "Motion resumed after system setting")
    }

    func testStillnessLiveAndLargestTextPortraitLandscape() {
        reveal()
        openSetting("Stillness Mode"); setToggle("stillness-toggle", true); app.buttons["Done"].tap()
        capture("Shadow Lord Stillness On")
        openSetting("Stillness Mode"); setToggle("stillness-toggle", false); app.buttons["Done"].tap()
        capture("Shadow Lord motion resumed")
        let inactive = app.staticTexts["ci-shadow-inactive"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", "Inactive intervals: [0-9]+; updates: 0; active frames: [1-9][0-9]*"), object: inactive)], timeout: 10), .completed)
        let priorIntervals = Int(inactive.label.components(separatedBy: ";")[0].components(separatedBy: ": ")[1])!
        XCUIDevice.shared.press(.home); settle(3); app.activate()
        XCTAssertTrue(element("bonus-card-quote").waitForExistence(timeout: 10))
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let parts = inactive.label.components(separatedBy: "; ")
            guard parts.count == 3, let count = Int(parts[0].components(separatedBy: ": ").last ?? "") else { return false }
            return count > priorIntervals && parts[1] == "updates: 0"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 10), .completed)
        capture("Inactive timeline update evidence")
        XCUIDevice.shared.orientation = .landscapeLeft
        settle()
        reachQuote()
        XCTAssertTrue(app.buttons["Settings"].isHittable)
        capture("Shadow Lord landscape")
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); openBonus(); reachQuote()
        capture("Shadow Lord largest text landscape")
        reachQuoteEnd()
        capture("Shadow Lord largest text landscape quote end")
        openSetting()
        XCTAssertTrue(app.switches["mischief-toggle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["mischief-toggle"].isHittable)
        capture("Mischievous Cards largest text landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.switches["mischief-toggle"].isHittable)
        capture("Mischievous Cards largest text portrait")
    }
}

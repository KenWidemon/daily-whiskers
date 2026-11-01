import XCTest
import UIKit

final class SavedCardsTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ci-smoke", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ci-smoke-offline"].waitForExistence(timeout: 15))
        clear()
    }
    override func tearDownWithError() throws { capture("Final test state"); app.terminate() }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
    private func clear() {
        app.buttons["Settings"].tap()
        let clear = app.buttons["Clear Saved Cards"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        guard clear.isEnabled else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.7)).tap()
            return
        }
        clear.tap()
        XCTAssertTrue(app.alerts["Clear Saved Cards?"].waitForExistence(timeout: 5))
        let confirm = app.alerts["Clear Saved Cards?"].buttons["Clear Saved Cards"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.buttons["daily-card-options"].waitForExistence(timeout: 5))
    }
    func testSaveRelaunchReopenShareRemoveAndConfirmedClear() {
        let save = app.buttons["daily-card-options"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        app.toggleDailyCardSave()
        XCTAssertTrue(waitForValue(save, "Saved"))
        capture("01 Today saved")
        app.terminate(); app.launch()
        XCTAssertTrue(waitForValue(app.buttons["daily-card-options"], "Saved"))
        app.buttons["open-saved-cards"].tap()
        let row = app.buttons["saved-card-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "saved-card-row").count, 1)
        capture("02 Saved Cards on this device")
        row.tap()
        XCTAssertTrue(app.buttons["saved-card-options"].waitForExistence(timeout: 10))
        swipeSavedContent()
        XCTAssertTrue(app.otherElements["saved-card-quote"].exists || app.staticTexts["saved-card-quote"].exists)
        capture("03 Reopened original full card")
        app.buttons["saved-card-options"].tap()
        let share = app.buttons["saved-card-share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertEqual(share.label, "Share Saved Card")
        recordShareAccessibilityBounds(share)
        capture("03 Saved card actions menu")
        share.tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        capture("04 Saved card system share")
        let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: UIDevice.current.userInterfaceIdiom == .pad ? 0.5 : 0.25))
        XCTAssertFalse(sheet.frame.contains(outside.screenPoint))
        outside.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sheet)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        let options = app.buttons["saved-card-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        let toggle = app.buttons["saved-card-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "Remove from Saved Cards")
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44)
        capture("05 Saved Card Options")
        dismissOptions()
        XCTAssertTrue(waitForOptionsValue("Saved"))
        options.tap(); toggle.tap()
        XCTAssertTrue(waitForOptionsValue("Not saved"))
        XCTAssertTrue(app.navigationBars["Card"].waitForExistence(timeout: 5))
        XCTAssertEqual(options.label, "Card Options")
        capture("06 Removed detail remains readable")
        options.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "Save Card")
        XCTAssertTrue(app.buttons["saved-card-share"].isHittable)
        XCTAssertEqual(app.buttons["saved-card-share"].label, "Share Card")
        capture("06 Unsaved detail Save Card menu")
        toggle.tap()
        XCTAssertTrue(waitForOptionsValue("Saved"))
        XCTAssertTrue(app.navigationBars["Saved Card"].waitForExistence(timeout: 5))
        XCTAssertEqual(options.label, "Saved Card Options")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(waitForOptionsValue("Saved"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap(); app.buttons["Clear Saved Cards"].tap()
        XCTAssertTrue(app.alerts["Clear Saved Cards?"].waitForExistence(timeout: 5))
        capture("06 Explicit clear confirmation")
        app.alerts["Clear Saved Cards?"].buttons["Cancel"].tap()
        XCTAssertTrue(waitForValue(app.buttons["daily-card-options"], "Saved"))
        clear()
        XCTAssertTrue(waitForValue(app.buttons["daily-card-options"], "Not saved"))
        app.buttons["open-saved-cards"].tap()
        XCTAssertTrue(app.staticTexts["saved-cards-empty"].waitForExistence(timeout: 5))
        capture("07 Empty collection")
    }
    func testClearEligibilityTracksSaveRemovalCancellationAndConfirmedClear() {
        let save = app.buttons["daily-card-options"]
        func checkClear(_ enabled: Bool, captureName: String) {
            app.buttons["Settings"].tap()
            let action = app.buttons["Clear Saved Cards"]
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertEqual(action.isEnabled, enabled)
            capture(captureName)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.7)).tap()
        }
        checkClear(false, captureName: "Clear disabled when empty")
        app.toggleDailyCardSave()
        XCTAssertTrue(waitForValue(save, "Saved"))
        app.assertDailySaveActionLabel("Remove from Saved Cards")
        checkClear(true, captureName: "Clear enabled with saved card")
        app.toggleDailyCardSave()
        XCTAssertTrue(waitForValue(save, "Not saved"))
        checkClear(false, captureName: "Clear disabled after last removal")
        app.toggleDailyCardSave()
        XCTAssertTrue(waitForValue(save, "Saved"))
        app.buttons["Settings"].tap(); app.buttons["Clear Saved Cards"].tap()
        let confirmation = app.alerts["Clear Saved Cards?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(waitForValue(save, "Saved"))
        checkClear(true, captureName: "Clear stays enabled after cancellation")
        clear()
        XCTAssertTrue(waitForValue(save, "Not saved"))
        checkClear(false, captureName: "Clear disabled after confirmed clear")
    }

    func testLargestTextSavedCardQuoteAndControlsRemainReachable() {
        app.toggleDailyCardSave()
        XCTAssertTrue(waitForValue(app.buttons["daily-card-options"], "Saved"))
        app.terminate()
        app.launchArguments = ["--ci-smoke", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["open-saved-cards"].waitForExistence(timeout: 10))
        capture("08 Largest text Today controls")
        app.buttons["open-saved-cards"].tap()
        let row = app.buttons["saved-card-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        capture("09 Largest text collection")
        row.tap()
        let quote = app.descendants(matching: .any)["saved-card-quote"].firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 10))
        // Large swipes can overshoot a tall quote; verify both readable boundaries
        // with the same toolbar-aware scrolling used by the paired-layout check.
        let vibe = app.descendants(matching: .any)["saved-card-vibe"].firstMatch
        captureScrollableQuote(quote, vibe: vibe, name: "10 Largest text saved card")
        XCTAssertTrue(app.buttons["saved-card-options"].isHittable)
        assertShareMenuAction()
    }
    func testLargestTextLandscapeSavedCardActionsAndVibe() {
        app.toggleDailyCardSave()
        XCTAssertTrue(waitForValue(app.buttons["daily-card-options"], "Saved"))
        app.terminate()
        app.launchArguments = ["--ci-smoke", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["open-saved-cards"].tap()
        app.buttons["saved-card-row"].firstMatch.tap()
        XCTAssertTrue(app.buttons["saved-card-options"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.windows.firstMatch.frame.width > self.app.windows.firstMatch.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed)
        let vibe = app.descendants(matching: .any)["saved-card-vibe"].firstMatch
        for _ in 0..<10 where !vibe.isHittable { swipeSavedContent() }
        capture("11 Largest text landscape saved card")
        XCTAssertTrue(vibe.isHittable)
        XCTAssertTrue(app.buttons["saved-card-options"].isHittable)
        assertShareMenuAction()
        XCUIDevice.shared.orientation = .portrait
    }

    private func swipeSavedContent() {
        // Keep gestures below navigation and above the smoke-test footer.
        let window = app.windows.firstMatch.frame
        let top = app.navigationBars.firstMatch.frame.maxY + 12
        let bottom = app.staticTexts["ci-smoke-offline"].frame.minY - 12
        XCTAssertGreaterThan(bottom, top)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: window.midX, dy: bottom))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: window.midX, dy: top)))
    }

    func testOrdinaryPortraitCardFitsWithoutScrolling() {
        let window = app.windows.firstMatch.frame
        let quote = app.descendants(matching: .any)["daily-card-quote"].firstMatch
        let vibe = app.descendants(matching: .any)["daily-card-vibe"].firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 10))
        XCTAssertTrue(window.contains(quote.frame))
        XCTAssertTrue(vibe.isHittable)
        let displayedQuote = quote.label
        let displayedVibe = vibe.label
        let todayBounds = cardBounds(prefix: "daily-card")
        assertSaveMenuToggle(captureName: "Bookmark-Standard")
        capture("12 Complete portrait Today card")
        app.toggleDailyCardSave()
        XCTAssertTrue(waitForValue(app.buttons["daily-card-options"], "Saved"))
        app.buttons["open-saved-cards"].tap()
        app.buttons.matching(identifier: "saved-card-row").firstMatch.tap()
        let savedQuote = app.descendants(matching: .any)["saved-card-quote"].firstMatch
        let savedVibe = app.descendants(matching: .any)["saved-card-vibe"].firstMatch
        let options = app.buttons["saved-card-options"]
        XCTAssertTrue(savedQuote.waitForExistence(timeout: 10))
        XCTAssertEqual(savedQuote.label, displayedQuote)
        XCTAssertEqual(savedVibe.label, displayedVibe)
        XCTAssertTrue(window.contains(savedQuote.frame))
        XCTAssertTrue(savedVibe.isHittable)
        XCTAssertLessThanOrEqual(savedVibe.frame.maxY, app.staticTexts["ci-smoke-offline"].frame.minY)
        XCTAssertTrue(options.isHittable)
        assertMatchingBounds(todayBounds, cardBounds(prefix: "saved-card"), name: "Standard matched card geometry")
        capture("13 Complete portrait saved card")
        assertOptionsActivation(captureName: "14 Saved Card Options")
    }

    func testLargestTextPairedGeometryAndOptions() {
        app.terminate()
        app.launchArguments = ["--ci-smoke", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ci-smoke-offline"].waitForExistence(timeout: 15))
        let quote = app.descendants(matching: .any)["daily-card-quote"].firstMatch
        let vibe = app.descendants(matching: .any)["daily-card-vibe"].firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 10))
        let originalQuote = quote.label, originalVibe = vibe.label
        let todayBounds = cardBounds(prefix: "daily-card")
        assertSaveMenuToggle(captureName: "Bookmark-AX5")
        capture("Pair-AX5-Today-Top")
        captureScrollableQuote(quote, vibe: vibe, name: "Pair-AX5-Today")
        app.toggleDailyCardSave()
        XCTAssertTrue(waitForValue(app.buttons["daily-card-options"], "Saved"))
        app.buttons["open-saved-cards"].tap()
        let row = app.buttons.matching(identifier: "saved-card-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let savedQuote = app.descendants(matching: .any)["saved-card-quote"].firstMatch
        let savedVibe = app.descendants(matching: .any)["saved-card-vibe"].firstMatch
        XCTAssertTrue(savedQuote.waitForExistence(timeout: 10))
        XCTAssertEqual(savedQuote.label, originalQuote)
        XCTAssertEqual(savedVibe.label, originalVibe)
        assertMatchingBounds(todayBounds, cardBounds(prefix: "saved-card"), name: "AX5 matched card geometry")
        capture("Pair-AX5-Saved-Top")
        captureScrollableQuote(savedQuote, vibe: savedVibe, name: "Pair-AX5-Saved")
        let options = app.buttons["saved-card-options"]
        XCTAssertTrue(options.isHittable)
        assertShareMenuAction()
        assertOptionsActivation(captureName: "Pair-AX5-Options")
    }

    private func assertSaveMenuToggle(captureName: String) {
        let save = app.buttons["daily-card-options"]
        app.assertDailySaveActionLabel("Save Card")
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(waitForValue(save, "Not saved"))
        let before = cardBounds(prefix: "daily-card")
        let controlFrame = save.frame
        capture(captureName + "-Unsaved")
        app.toggleDailyCardSave()
        XCTAssertTrue(waitForValue(save, "Saved"))
        app.assertDailySaveActionLabel("Remove from Saved Cards")
        XCTAssertEqual(save.frame, controlFrame)
        XCTAssertTrue(save.isHittable)
        assertMatchingBounds(before, cardBounds(prefix: "daily-card"), name: captureName + " toggle geometry")
        capture(captureName + "-Saved")
        app.toggleDailyCardSave()
        XCTAssertTrue(waitForValue(save, "Not saved"))
        app.assertDailySaveActionLabel("Save Card")
        XCTAssertEqual(save.frame, controlFrame)
        XCTAssertEqual(cardBounds(prefix: "daily-card"), before)
    }

    private func cardBounds(prefix: String) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: ["frame", "quote", "vibe"].map {
            ($0, app.descendants(matching: .any)["\(prefix)-\($0)"].firstMatch.frame)
        })
    }

    private func assertMatchingBounds(_ today: [String: CGRect], _ saved: [String: CGRect], name: String) {
        var rows: [[String: Any]] = []
        for key in ["frame", "quote", "vibe"] {
            let a = today[key]!, b = saved[key]!
            XCTAssertGreaterThan(a.width, 0); XCTAssertGreaterThan(a.height, 0)
            XCTAssertEqual(a.minX, b.minX, accuracy: 1, key + " x")
            XCTAssertEqual(a.minY, b.minY, accuracy: 1, key + " y")
            XCTAssertEqual(a.width, b.width, accuracy: 1, key + " width")
            XCTAssertEqual(a.height, b.height, accuracy: 1, key + " height")
            rows.append(["element": key, "today": [a.minX,a.minY,a.width,a.height], "saved": [b.minX,b.minY,b.width,b.height]])
        }
        let data = try! JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted,.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func recordShareAccessibilityBounds(_ share: XCUIElement) {
        // The native menu's AX frame is metadata, not proof of its tap boundaries.
        let b = share.frame
        let data = try! JSONSerialization.data(withJSONObject:
            ["x": b.minX, "y": b.minY, "width": b.width, "height": b.height])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Share menu accessibility bounds"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertShareMenuAction() {
        app.buttons["saved-card-options"].tap()
        let share = app.buttons["saved-card-share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertEqual(share.label, "Share Saved Card")
        XCTAssertTrue(share.isHittable)
        recordShareAccessibilityBounds(share)
        dismissOptions()
    }

    private func assertOptionsActivation(captureName: String) {
        let options = app.buttons["saved-card-options"]
        XCTAssertEqual(options.label, "Saved Card Options")
        XCTAssertTrue(options.isHittable)
        XCTAssertTrue(waitForOptionsValue("Saved"))
        let bounds = options.frame
        let data = try! JSONSerialization.data(withJSONObject: ["x":bounds.minX,"y":bounds.minY,"width":bounds.width,"height":bounds.height], options:[.prettyPrinted,.sortedKeys])
        let attachment = XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
        attachment.name = captureName + " trigger accessibility bounds"; attachment.lifetime = .keepAlways; add(attachment)
        let remove = app.buttons["saved-card-toggle"]
        let origin = app.coordinate(withNormalizedOffset: .zero)
        // Half a point inside the 44-point perimeter avoids an exclusive max edge.
        // Coordinate taps exercise the hit region; AX bounds only locate its center.
        let edge: CGFloat = 21.5
        let samples: [(String, CGFloat, CGFloat)] = [
            ("center", 0, 0), ("top", 0, -edge), ("bottom", 0, edge),
            ("left", -edge, 0), ("right", edge, 0),
            ("top-left", -edge, -edge), ("top-right", edge, -edge),
            ("bottom-left", -edge, edge), ("bottom-right", edge, edge),
            ("center-after-edges", 0, 0)
        ]
        var observations: [[String: Any]] = []
        defer {
            let data = try! JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = captureName + " 44-point coordinate taps"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        for (name, dx, dy) in samples {
            XCTAssertEqual(options.frame, bounds, "Options geometry changed before \(name)")
            let point = CGPoint(x: bounds.midX + dx, y: bounds.midY + dy)
            let anchor = origin.screenPoint
            origin.withOffset(CGVector(dx: point.x - anchor.x, dy: point.y - anchor.y)).tap()
            let opened = remove.waitForExistence(timeout: 5)
            observations.append(["sample": name, "x": point.x, "y": point.y, "opened": opened])
            XCTAssertTrue(opened, "Options did not open at \(name) of the 44-point target: \(point)")
            XCTAssertEqual(remove.label, "Remove from Saved Cards")
            XCTAssertTrue(remove.isHittable)
            XCTAssertGreaterThanOrEqual(remove.frame.height, 44)
            if name == "center" { capture(captureName) }
            dismissOptions()
            XCTAssertTrue(waitForOptionsValue("Saved"))
        }
    }

    private func dismissOptions() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.7)).tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["saved-card-toggle"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }

    private func waitForOptionsValue(_ value: String) -> Bool {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: app.buttons["saved-card-options"])
        return XCTWaiter.wait(for: [expected], timeout: 10) == .completed
    }

    // Verify both boundaries of long quotes through scrolling at their requested size.
    private func captureScrollableQuote(_ quote: XCUIElement, vibe: XCUIElement, name: String,
                                        landscape: Bool? = nil) {
        let scroll = app.scrollViews[quote.identifier.replacingOccurrences(of: "-quote", with: "-content")]
        // Rotation can expose intermediate window, toolbar and footer frames.
        // Wait for a consistent viewport; never activate an app displaced by a bad gesture.
        func settledBounds() -> CGRect? {
            var previous: [CGRect] = []
            var stableSince = Date()
            var bounds: CGRect?
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard self.app.state == .runningForeground, scroll.exists else { return false }
                let window = self.app.windows.firstMatch.frame
                let navigation = self.app.navigationBars.firstMatch.frame
                let footer = self.app.staticTexts["ci-smoke-offline"].frame
                let content = scroll.frame
                let frames = [window, navigation, footer, content]
                if frames != previous {
                    previous = frames
                    stableSince = Date()
                    return false
                }
                if let landscape, (window.width > window.height) != landscape { return false }
                let visible = window.intersection(content)
                let top = max(visible.minY, navigation.maxY + 8)
                let bottom = min(visible.maxY, footer.minY - 4)
                guard !visible.isNull, visible.width > 40, bottom - top > 40,
                      Date().timeIntervalSince(stableSince) >= 0.5 else { return false }
                bounds = CGRect(x: visible.minX, y: top, width: visible.width, height: bottom - top)
                return true
            }, object: nil)
            let result = XCTWaiter.wait(for: [settled], timeout: 10)
            XCTAssertEqual(result, .completed, "Scrollable viewport did not settle in the foreground")
            return result == .completed ? bounds : nil
        }
        guard let initial = settledBounds() else { return }
        var top = initial.minY
        var bottom = initial.maxY
        func drag(_ amount: (CGRect) -> CGFloat) -> Bool {
            guard let bounds = settledBounds() else { return false }
            top = bounds.minY
            bottom = bounds.maxY
            let delta = amount(bounds)
            let distance = min(abs(delta), bottom - top - 40)
            let startY = delta > 0 ? bottom - 20 : top + 20
            let endY = startY + (delta > 0 ? -distance : distance)
            let start = CGPoint(x: bounds.midX, y: startY)
            let end = CGPoint(x: bounds.midX, y: endY)
            XCTAssertTrue(bounds.contains(start))
            XCTAssertTrue(bounds.contains(end))
            let window = app.windows.firstMatch.frame
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            XCTContext.runActivity(named: "Scroll in window \(window) within \(bounds), from \(start) to \(end)") { _ in
                origin.withOffset(CGVector(dx: start.x - window.minX, dy: start.y - window.minY))
                    .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: end.x - window.minX, dy: end.y - window.minY)),
                           withVelocity: .slow, thenHoldForDuration: 0.25)
            }
            XCTAssertEqual(app.state, .runningForeground, "Scrolling left the app")
            return app.state == .runningForeground
        }
        for _ in 0..<12 where abs(quote.frame.minY - (top + 8)) > 12 {
            let previous = quote.frame.minY
            guard drag({ quote.frame.minY - ($0.minY + 8) }) else { return }
            if abs(quote.frame.minY - previous) < 1 { break }
        }
        XCTAssertGreaterThanOrEqual(quote.frame.minY, top - 4)
        XCTAssertLessThan(quote.frame.minY, bottom - 40)
        capture(name + "-Quote-Start")
        for _ in 0..<12 where vibe.frame.maxY > bottom || vibe.frame.minY < top {
            guard drag({ max(32, vibe.frame.maxY - ($0.maxY - 4)) }) else { return }
        }
        XCTAssertGreaterThan(quote.frame.maxY, top + 40)
        XCTAssertLessThanOrEqual(quote.frame.maxY, bottom)
        XCTAssertGreaterThanOrEqual(vibe.frame.minY, top)
        XCTAssertLessThanOrEqual(vibe.frame.maxY, bottom)
        XCTAssertTrue(vibe.isHittable)
        capture(name + "-Quote")
    }

    // Deterministic bundled extremes keep layout evidence independent of the date.
    func testAdaptiveCardAndSavedTilesAcrossWindowSizes() throws {
        var labels: [String] = []
        for fixture in ["shortest", "longest"] {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
            app.launchArguments = ["--ci-smoke", "--ci-smoke-\(fixture)-card",
                                   "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launch()
            let quote = app.descendants(matching: .any)["daily-card-quote"].firstMatch
            XCTAssertTrue(quote.waitForExistence(timeout: 10))
            labels.append(quote.label)
            let bottom = app.staticTexts["ci-smoke-offline"].frame.minY
            if app.descendants(matching: .any)["daily-card-frame"].firstMatch.frame.maxY <= bottom {
                assertCardVisible(prefix: "daily-card")
            } else {
                captureScrollableQuote(quote, vibe: app.descendants(matching: .any)["daily-card-vibe"].firstMatch,
                                       name: "Compact portrait \(fixture)", landscape: false)
            }
            capture("Window \(fixture) portrait")
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.app.windows.firstMatch.frame.width > self.app.windows.firstMatch.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
            if app.windows.firstMatch.frame.height >= 800 {
                assertCardVisible(prefix: "daily-card")
                XCTAssertGreaterThan(app.descendants(matching: .any)["daily-card-frame"].firstMatch.frame.width, 800)
            } else {
                captureScrollableQuote(quote, vibe: app.descendants(matching: .any)["daily-card-vibe"].firstMatch,
                                       name: "Narrow landscape \(fixture)", landscape: true)
            }
            XCTAssertEqual(quote.label, labels.last)
            capture("Window \(fixture) landscape")
            let save = app.buttons["daily-card-options"]
            if save.value as? String != "Saved" { app.toggleDailyCardSave() }
            XCTAssertTrue(waitForValue(save, "Saved"))
        }
        XCUIDevice.shared.orientation = .portrait
        app.buttons["open-saved-cards"].tap()
        let rows = app.buttons.matching(identifier: "saved-card-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.allElementsBoundByIndex.map(\.label)), Set(labels))
        if app.windows.firstMatch.frame.width >= 660 { assertAlignedTiles(rows) }
        else { XCTAssertGreaterThan(rows.element(boundBy: 1).frame.minY, rows.element(boundBy: 0).frame.maxY) }
        capture("Window short and long Saved tiles portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        // Every multi-column collection reserves equal quote areas, including opened phones.
        if app.windows.firstMatch.frame.width >= 660 { assertAlignedTiles(rows) }
        capture("Window short and long Saved tiles landscape")
        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["saved-card-options"].waitForExistence(timeout: 10))
        if app.windows.firstMatch.frame.height >= 800 { assertCardVisible(prefix: "saved-card") }
        else {
            captureScrollableQuote(app.descendants(matching: .any)["saved-card-quote"].firstMatch,
                                   vibe: app.descendants(matching: .any)["saved-card-vibe"].firstMatch,
                                   name: "Narrow saved detail", landscape: true)
        }
        capture("Window longest saved detail landscape")

        if UIDevice.current.userInterfaceIdiom == .pad {
            let full = app.windows.firstMatch.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: full.maxX - 5, dy: full.maxY - 5))
                .press(forDuration: 0.4, thenDragTo: origin.withOffset(CGVector(dx: full.minX + 650, dy: full.maxY - 100)),
                       withVelocity: .slow, thenHoldForDuration: 0.4)
            let narrowed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.app.windows.firstMatch.frame.width < 800
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [narrowed], timeout: 10), .completed)
            capture("Actual narrow window retained saved card")
            XCTAssertEqual(app.descendants(matching: .any)["saved-card-quote"].firstMatch.label, labels.last)
            XCTAssertTrue(waitForOptionsValue("Saved"))
            captureScrollableQuote(app.descendants(matching: .any)["saved-card-quote"].firstMatch,
                                   vibe: app.descendants(matching: .any)["saved-card-vibe"].firstMatch,
                                   name: "Actual narrow window")
            let narrow = app.windows.firstMatch.frame
            origin.withOffset(CGVector(dx: narrow.maxX - 5, dy: narrow.maxY - 5))
                .press(forDuration: 0.4, thenDragTo: origin.withOffset(CGVector(dx: full.maxX - 5, dy: full.maxY - 5)),
                       withVelocity: .slow, thenHoldForDuration: 0.4)
            let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.app.windows.firstMatch.frame.width > 1000
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
            XCTAssertEqual(app.descendants(matching: .any)["saved-card-quote"].firstMatch.label, labels.last)
            XCTAssertTrue(waitForOptionsValue("Saved"))
            capture("Actual wide window restored saved card")
        }

        app.terminate()
        app.launchArguments = ["--ci-smoke", "--ci-smoke-longest-card",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["open-saved-cards"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        app.buttons["open-saved-cards"].tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 2)
        let first = rows.element(boundBy: 0), second = rows.element(boundBy: 1)
        XCTAssertEqual(first.frame.minX, second.frame.minX, accuracy: 1)
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 1)
        XCTAssertGreaterThan(second.frame.minY, first.frame.maxY)
        XCTAssertEqual(Set(rows.allElementsBoundByIndex.map(\.label)), Set(labels))
        capture("iPad accessibility full quotes single column")
        first.tap()
        let quote = app.descendants(matching: .any)["saved-card-quote"].firstMatch
        let vibe = app.descendants(matching: .any)["saved-card-vibe"].firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 10))
        XCTAssertEqual(quote.label, labels.last)
        captureScrollableQuote(quote, vibe: vibe, name: "iPad longest accessibility portrait", landscape: false)
        XCUIDevice.shared.orientation = .landscapeLeft
        captureScrollableQuote(quote, vibe: vibe, name: "iPad longest accessibility landscape", landscape: true)
    }

    // Run once per native Device Hub pose. XCUIDevice's sensor orientation alone
    // does not resize the Duo simulator's active display/window.
    func testAdaptiveCardsInCurrentWindow() {
        var labels: [String] = []
        for fixture in ["shortest", "longest"] {
            app.terminate()
            app.launchArguments = ["--ci-smoke", "--ci-smoke-\(fixture)-card",
                                   "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launch()
            XCTAssertTrue(app.staticTexts["ci-smoke-offline"].waitForExistence(timeout: 15))
            let quote = app.descendants(matching: .any)["daily-card-quote"].firstMatch
            XCTAssertTrue(quote.waitForExistence(timeout: 10))
            labels.append(quote.label)
            checkCurrentCard(prefix: "daily-card", name: fixture)
            app.toggleDailyCardSave()
            XCTAssertTrue(waitForValue(app.buttons["daily-card-options"], "Saved"))
            XCTAssertEqual(quote.label, labels.last)
        }
        app.buttons["open-saved-cards"].tap()
        let rows = app.buttons.matching(identifier: "saved-card-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.allElementsBoundByIndex.map(\.label)), Set(labels))
        if abs(rows.element(boundBy: 0).frame.minY - rows.element(boundBy: 1).frame.minY) < 1 {
            assertAlignedTiles(rows)
        } else {
            XCTAssertGreaterThan(rows.element(boundBy: 1).frame.minY, rows.element(boundBy: 0).frame.maxY)
        }
        capture("Current native window Saved collection")
        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["saved-card-options"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any)["saved-card-quote"].firstMatch.label, labels.last)
        XCTAssertTrue(waitForOptionsValue("Saved"))
        checkCurrentCard(prefix: "saved-card", name: "Retained longest")
        app.openCardOptions()
        app.buttons["saved-card-share"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 15))
        capture("Current native window retained share")
        let dismiss = app.otherElements["PopoverDismissRegion"]
        if dismiss.exists {
            // Resolve the active display through its element, not main-screen coordinates.
            XCTAssertTrue(dismiss.isHittable)
            dismiss.tap()
        } else if app.buttons["Close"].firstMatch.isHittable {
            app.buttons["Close"].firstMatch.tap()
        } else {
            let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.20))
            XCTAssertFalse(sheet.frame.contains(outside.screenPoint))
            outside.tap()
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: sheet)], timeout: 10), .completed)
        XCTAssertTrue(app.buttons["saved-card-options"].isHittable)
        XCTAssertTrue(waitForOptionsValue("Saved"))
    }

    private func checkCurrentCard(prefix: String, name: String) {
        let card = app.descendants(matching: .any)["\(prefix)-frame"].firstMatch
        let quote = app.descendants(matching: .any)["\(prefix)-quote"].firstMatch
        let vibe = app.descendants(matching: .any)["\(prefix)-vibe"].firstMatch
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(card.frame.width, window.width)
        if card.frame.maxY <= app.staticTexts["ci-smoke-offline"].frame.minY {
            assertCardVisible(prefix: prefix)
        } else {
            captureScrollableQuote(quote, vibe: vibe, name: name,
                                   landscape: window.width > window.height)
        }
        capture("Current native window \(name)")
    }

    private func assertCardVisible(prefix: String) {
        let quote = app.descendants(matching: .any)["\(prefix)-quote"].firstMatch
        let vibe = app.descendants(matching: .any)["\(prefix)-vibe"].firstMatch
        let card = app.descendants(matching: .any)["\(prefix)-frame"].firstMatch
        XCTAssertTrue(vibe.waitForExistence(timeout: 5))
        let top = app.navigationBars.firstMatch.frame.maxY
        let bottom = app.staticTexts["ci-smoke-offline"].frame.minY
        XCTAssertGreaterThanOrEqual(card.frame.minY, top)
        XCTAssertLessThanOrEqual(card.frame.maxY, bottom)
        XCTAssertGreaterThanOrEqual(quote.frame.minY, top)
        XCTAssertLessThanOrEqual(vibe.frame.maxY, bottom)
        XCTAssertTrue(vibe.isHittable)
    }

    private func assertAlignedTiles(_ rows: XCUIElementQuery) {
        let first = rows.element(boundBy: 0).frame, second = rows.element(boundBy: 1).frame
        XCTAssertEqual(first.minY, second.minY, accuracy: 1)
        XCTAssertEqual(first.maxY, second.maxY, accuracy: 1)
        XCTAssertEqual(first.width, second.width, accuracy: 1)
    }

    private func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter.wait(for: [expected], timeout: 10) == .completed
    }
}

// Shared UI navigation for card actions; state is exposed on the persistent trigger.
extension XCUIApplication {
    @discardableResult
    func openCardOptions() -> XCUIElement {
        let options = buttons["saved-card-options"].exists ? buttons["saved-card-options"] : buttons["daily-card-options"]
        if !buttons["share-daily-card"].exists && !buttons["saved-card-share"].exists {
            XCTAssertTrue(options.waitForExistence(timeout: 10))
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: options)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
            XCTAssertTrue(options.isHittable)
            options.tap()
        }
        return options
    }

    func dismissCardOptions() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.7)).tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !self.buttons["share-daily-card"].exists && !self.buttons["saved-card-share"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }

    func toggleDailyCardSave() {
        XCTAssertTrue(buttons["daily-card-options"].exists)
        openCardOptions()
        let action = buttons["save-daily-card"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isHittable)
        action.tap()
    }

    func assertDailySaveActionLabel(_ label: String) {
        openCardOptions()
        let action = buttons["save-daily-card"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(action.label, label)
        XCTAssertTrue(action.isHittable)
        dismissCardOptions()
    }
}

/// Isolated issue #115 fixtures never clear or seed the ordinary app collection.
final class SavedCardsLoadStateTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }
    override func tearDownWithError() throws {
        capture("Saved load final state")
        app.terminate()
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
    private var empty: XCUIElement { app.staticTexts["saved-cards-empty"] }
    private var unavailable: XCUIElement { app.descendants(matching: .any)["saved-cards-unavailable"].firstMatch }
    private var rows: XCUIElementQuery { app.buttons.matching(identifier: "saved-card-row") }
    private func launch(largestText: Bool = false, emptyFixture: Bool = false,
                        interruptedRetry: Bool = false) {
        app.launchEnvironment["DW_SAVED_LOAD_TEST_ID"] = UUID().uuidString
        app.launchArguments = ["--ci-smoke", "--ci-smoke-saved-load-fixture",
            "-UIPreferredContentSizeCategoryName",
            largestText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        if emptyFixture { app.launchArguments.append("--ci-smoke-saved-empty-fixture") }
        if interruptedRetry { app.launchArguments.append("--ci-smoke-saved-interrupted-retry") }
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["saved-cards-loading"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(empty.exists)
        XCTAssertEqual(rows.count, 0)
        capture("Saved loading before first read")
        let finish = app.buttons["fixture-finish-read"]
        XCTAssertTrue(finish.isHittable)
        XCTAssertGreaterThanOrEqual(finish.frame.height, 44)
        XCTAssertFalse(finish.frame.intersects(app.staticTexts["ci-smoke-offline"].frame))
        finish.tap()
        dismissError()
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        XCTAssertFalse(empty.exists)
        XCTAssertEqual(rows.count, 0)
        capture("Saved unavailable after alert dismissal")
    }
    private func dismissError() {
        let alert = app.alerts["Couldn't Update Saved Cards"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Cancel"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: alert)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }
    private func retry() {
        let retry = app.buttons["saved-cards-retry"]
        XCTAssertTrue(retry.exists)
        for _ in 0..<8 where !retry.isHittable { app.scrollViews["saved-cards-collection"].swipeUp() }
        XCTAssertTrue(retry.isHittable)
        XCTAssertEqual(retry.label, "Retry")
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        capture("Saved accessible in-place Retry")
        retry.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: unavailable)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
    }
    func testFailedFirstReadDismissRetryAndLaterRefreshPreserveRows() {
        launch()
        retry()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.allElementsBoundByIndex.map(\.label), ["Second saved fixture.", "First saved fixture."])
        let ids = rows.allElementsBoundByIndex.map { $0.value as? String }
        XCTAssertTrue(ids.allSatisfy { $0?.isEmpty == false })
        XCTAssertEqual(Set(ids).count, 2)
        capture("Saved recovered original rows")
        app.buttons["fixture-refresh"].tap()
        dismissError()
        XCTAssertTrue(unavailable.exists)
        XCTAssertFalse(empty.exists)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.allElementsBoundByIndex.map { $0.value as? String }, ids)
        XCTAssertEqual(app.staticTexts["saved-cards-read-status"].label,
                       "Showing previously loaded cards. Retry to check for updates.")
        capture("Saved stale rows after refresh failure")
        retry()
        XCTAssertEqual(rows.allElementsBoundByIndex.map { $0.value as? String }, ids)
        XCTAssertEqual(rows.allElementsBoundByIndex.map(\.label), ["Second saved fixture.", "First saved fixture."])
        rows.firstMatch.tap()
        let quote = app.descendants(matching: .any)["saved-card-quote"].firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 10))
        XCTAssertEqual(quote.label, "Second saved fixture.")
        capture("Saved recovered retained detail")
    }
    func testLargestTextUnavailableRetryRemainsReachable() {
        launch(largestText: true)
        retry()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 2)
        XCTAssertFalse(empty.exists)
        capture("Saved largest text recovered collection")
    }
    func testInterruptedAndRepeatedRetryKeepsRecoveryAvailable() {
        launch(interruptedRetry: true)
        app.buttons["saved-cards-retry"].tap()
        let loading = app.descendants(matching: .any)["saved-cards-loading"].firstMatch
        XCTAssertTrue(loading.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saved-cards-retry"].exists)
        XCTAssertFalse(empty.exists)
        // Requests during the held read must not queue another read or mutation.
        app.buttons["fixture-refresh"].tap()
        app.buttons["fixture-refresh"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(loading.waitForExistence(timeout: 5))
        capture("Saved Retry in progress after foregrounding")
        app.buttons["fixture-finish-read"].tap()
        dismissError()
        XCTAssertTrue(unavailable.exists)
        XCTAssertFalse(empty.exists)
        XCTAssertEqual(rows.count, 0)
        XCTAssertTrue(app.buttons["saved-cards-retry"].isHittable)
        capture("Saved interrupted Retry remains available")
        // The next read fails again; only the following read succeeds.
        app.buttons["saved-cards-retry"].tap()
        dismissError()
        XCTAssertTrue(unavailable.exists)
        XCTAssertFalse(empty.exists)
        retry()
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.allElementsBoundByIndex.map(\.label), ["Second saved fixture.", "First saved fixture."])
        XCTAssertEqual(Set(rows.allElementsBoundByIndex.compactMap { $0.value as? String }).count, 2)
        capture("Saved repeated Retry restores original collection")
    }
    func testOnlySuccessfulEmptyReadShowsEmptyGuidance() {
        launch(emptyFixture: true)
        retry()
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 0)
        capture("Saved verified empty collection")
        app.buttons["fixture-refresh"].tap()
        dismissError()
        XCTAssertTrue(unavailable.exists)
        XCTAssertFalse(empty.exists)
        retry()
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
    }
}

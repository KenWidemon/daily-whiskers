import XCTest
import UIKit

@MainActor
final class DailyCardSharingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if let run = testRun, run.failureCount > 0 {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testActualExportPayloadsForTodayBonusAndSaved() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--ci-smoke", "--ci-smoke-export-evidence", "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        app.launch()
        XCTAssertTrue(app.staticTexts["ci-smoke-offline"].waitForExistence(timeout: 15))
        let daily = app.descendants(matching: .any)["daily-card-quote"].firstMatch
        XCTAssertTrue(daily.waitForExistence(timeout: 10))
        let todayQuote = daily.label
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertTrue(app.windows.firstMatch.frame.contains(app.descendants(matching: .any)["daily-card-frame"].firstMatch.frame))
        }
        captureExportReview("01-Today-app")
        shareAndCancel("02-Today-system-sheet", button: app.buttons["share-daily-card"])
        saveCurrentCard()
        let menu = app.buttons["card-menu"]
        menu.tap(); app.buttons["Open Bonus Card"].tap()
        let bonus = app.descendants(matching: .any)["bonus-card-quote"].firstMatch
        XCTAssertTrue(bonus.waitForExistence(timeout: 15))
        let bonusQuote = bonus.label
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertTrue(app.windows.firstMatch.frame.contains(app.descendants(matching: .any)["bonus-card-frame"].firstMatch.frame))
        }
        XCTAssertNotEqual(todayQuote, bonusQuote)
        captureExportReview("03-Bonus-app")
        shareAndCancel("04-Bonus-system-sheet", button: app.buttons["share-daily-card"])
        saveCurrentCard()
        for (index, quote) in [bonusQuote, todayQuote].enumerated() {
            if index > 0 { app.terminate(); app.launch() }
            app.buttons["open-saved-cards"].tap()
            let row = app.buttons.matching(identifier: "saved-card-row").matching(NSPredicate(format: "label == %@", quote)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
            let saved = app.descendants(matching: .any)["saved-card-quote"].firstMatch
            XCTAssertTrue(saved.waitForExistence(timeout: 10)); XCTAssertEqual(saved.label, quote)
            captureExportReview("05-Saved-\(index)-app")
            shareAndCancel("06-Saved-\(index)-system-sheet", button: app.buttons["Share Saved Card"])
        }
    }

    func testLongestQuoteExportRetryCancelAndLargerText() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--ci-smoke", "--ci-smoke-export-evidence", "--ci-smoke-longest-card", "--ci-smoke-share-failure-once", "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        app.launch()
        XCTAssertTrue(app.staticTexts["ci-smoke-offline"].waitForExistence(timeout: 15))
        let share = app.buttons["share-daily-card"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        let ready = NSPredicate { _, _ in share.isEnabled }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 15), .completed)
        captureExportReview("07-Longest-quote-app")
        share.tap()
        let error = app.alerts["Couldn't Share Card"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        captureExportReview("08-Injected-render-error")
        error.buttons["Try Again"].tap()
        cancelExportSheet("09-Longest-quote-retry-sheet")
        shareAndCancel("10-Longest-quote-second-share", button: share)
        app.terminate()
        app.launchArguments = ["--ci-smoke", "--ci-smoke-export-evidence", "--ci-smoke-longest-card", "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        app.launch()
        XCTAssertTrue(app.staticTexts["ci-smoke-offline"].waitForExistence(timeout: 15))
        captureExportReview("11-Largest-text-top")
        checkLongQuoteEdges()
        captureExportReview("12-Largest-text-quote")
        shareAndCancel("13-Largest-text-scrolled-sheet", button: share)
    }

    private func checkLongQuoteEdges() {
        let quote = app.descendants(matching: .any)["daily-card-quote"].firstMatch, vibe = app.descendants(matching: .any)["daily-card-vibe"].firstMatch
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
        captureExportReview("12-Largest-text-quote-start")
        for _ in 0..<12 where vibe.frame.maxY > bottom || vibe.frame.minY < top {
            drag(max(32, vibe.frame.maxY - (bottom - 4)))
        }
        XCTAssertGreaterThan(quote.frame.maxY, top + 40)
        XCTAssertLessThanOrEqual(quote.frame.maxY, bottom)
        XCTAssertGreaterThanOrEqual(vibe.frame.minY, top)
        XCTAssertLessThanOrEqual(vibe.frame.maxY, bottom)
        XCTAssertTrue(vibe.isHittable)
        captureExportReview("12-Largest-text-quote-end")
    }

    private func saveCurrentCard() {
        let button = app.buttons["save-daily-card"]
        if button.value as? String != "Saved" { button.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Saved"), object: button)], timeout: 10), .completed)
    }

    private func captureExportReview(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    private func shareAndCancel(_ name: String, button: XCUIElement) {
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let ready = NSPredicate { _, _ in button.isEnabled && button.isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 15), .completed)
        button.tap(); cancelExportSheet(name)
        XCTAssertTrue(button.isEnabled)
        XCTAssertFalse(app.alerts["Couldn't Share Card"].exists)
    }

    private func cancelExportSheet(_ name: String) {
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 15))
        var last = CGRect.null
        let settled = NSPredicate { _, _ in
            let frame = sheet.frame
            defer { last = frame }
            return !frame.isEmpty && frame == last
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 10), .completed)
        captureExportReview(name)
        let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: UIDevice.current.userInterfaceIdiom == .pad ? 0.5 : 0.25))
        XCTAssertFalse(sheet.frame.contains(outside.screenPoint)); outside.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sheet)], timeout: 10), .completed)
    }

    func testGuestCanCancelSharingAndShareAgain() {
        checkCancellation(orientation: .portrait, textSize: .large)
    }

    func testShareActionAndSheetAtLargestTextInLandscape() {
        checkCancellation(orientation: .landscapeLeft, textSize: .accessibilityExtraExtraExtraLarge)
    }

    func testShareSheetRemainsUsableAcrossRotation() {
        checkCancellation(orientation: .portrait, textSize: .large, rotateWhilePresented: true)
    }

    func testAccountSheetKeepsLocalNavigationUsableAcrossReopening() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        app.launch()
        let settings = app.buttons["Settings"]
        for _ in 0..<2 {
            XCTAssertTrue(settings.waitForExistence(timeout: 10))
            XCTAssertTrue(settings.isHittable)
            settings.tap()
            let signIn = app.buttons["Sign In"]
            XCTAssertTrue(signIn.waitForExistence(timeout: 5))
            signIn.tap()
            let form = app.scrollViews["auth-form"]
            XCTAssertTrue(form.waitForExistence(timeout: 5))
            // XCTest includes the covered toolbar in its UI hierarchy; this checks
            // interaction isolation, not VoiceOver focus eligibility.
            let excluded = NSPredicate { _, _ in !settings.isHittable }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: excluded, object: nil)], timeout: 5), .completed)
            XCTAssertTrue(app.buttons["Close"].isHittable)

            // Empty-email validation stays local; no reset email is requested.
            tapInForm(app.buttons["Forgot password?"])
            XCTAssertTrue(app.staticTexts["Enter a valid email address."].waitForExistence(timeout: 5))
            XCTAssertFalse(app.alerts["Check Your Email"].exists)
            XCTAssertFalse(settings.isHittable)
            tapInForm(app.buttons["Create Account"])
            XCTAssertTrue(app.textFields["registration-email"].waitForExistence(timeout: 5))
            XCTAssertFalse(settings.isHittable)
            tapInForm(app.buttons["Back to Sign In"])
            XCTAssertTrue(app.buttons["Forgot password?"].waitForExistence(timeout: 5))
            XCTAssertFalse(settings.isHittable)
            app.buttons["Close"].tap()
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            XCTAssertFalse(form.exists)
            XCTAssertTrue(app.buttons["share-daily-card"].isHittable)
        }
        // Accessibility-tree/navigation evidence, not VoiceOver focus timing or speech.
    }

    func testDailyCanvasRotationFromPortrait() {
        checkDailyCanvasRotation(initial: .portrait)
    }

    func testDailyCanvasRotationFromLandscape() {
        checkDailyCanvasRotation(initial: .landscapeLeft)
    }

    private func checkDailyCanvasRotation(initial: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = initial
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        app.launch()
        let card = app.otherElements["daily-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let other: UIDeviceOrientation = initial == .portrait ? .landscapeLeft : .portrait
        for (index, orientation) in [initial, other, initial, other, initial].enumerated() {
            XCUIDevice.shared.orientation = orientation
            let landscape = orientation == .landscapeLeft
            let window = app.windows.firstMatch
            let rotated = NSPredicate { _, _ in
                let frame = window.frame
                return landscape ? frame.width > frame.height : frame.height > frame.width
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: rotated, object: nil)], timeout: 10), .completed)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Main canvas rotation \(initial.rawValue)-\(index)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            print("ROTATION \(index) orientation=\(orientation.rawValue) window=\(window.frame) card=\(card.frame)")
            XCTAssertEqual(card.frame.width, window.frame.width, accuracy: 2, "Daily canvas must follow current window width.")
            XCTAssertEqual(card.frame.midX, window.frame.midX, accuracy: 2, "Daily canvas must stay centered after rotation.")
            XCTAssertLessThanOrEqual(card.frame.maxY, window.frame.maxY + 2, "Daily canvas viewport cannot extend beyond the current window.")
            checkQuoteRemainsReachable()
            XCTAssertTrue(app.buttons["Settings"].isHittable)
            XCTAssertTrue(app.buttons["share-daily-card"].isHittable)
        }
    }

    private func checkQuoteRemainsReachable() {
        let quote = app.descendants(matching: .any)["daily-card-quote"].firstMatch
        let window = app.windows.firstMatch
        XCTAssertTrue(quote.exists)
        XCTAssertEqual(quote.frame.midX, window.frame.midX, accuracy: 2, "Artwork and quote must follow the current window center.")
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<5 where !window.frame.contains(quote.frame) { scroll.swipeUp() }
        XCTAssertTrue(window.frame.contains(quote.frame), "The complete quote must be reachable after rotation.")
        let vibe = app.descendants(matching: .any)["daily-card-vibe"].firstMatch
        if vibe.exists {
            for _ in 0..<5 where !window.frame.contains(vibe.frame) { scroll.swipeUp() }
            XCTAssertTrue(window.frame.contains(vibe.frame), "The vibe must remain reachable after rotation.")
        }
    }

    private func tapInForm(_ element: XCUIElement) {
        let form = app.scrollViews["auth-form"]
        for _ in 0..<8 where !element.isHittable { form.swipeUp() }
        XCTAssertTrue(element.isHittable)
        element.tap()
    }

    private func checkCancellation(orientation: UIDeviceOrientation, textSize: UIContentSizeCategory, rotateWhilePresented: Bool = false) {
        var currentOrientation = orientation
        XCUIDevice.shared.orientation = orientation
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", textSize.rawValue]
        app.launch()
        let share = app.buttons["share-daily-card"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertEqual(share.label, "Share Today's Card")
        XCTAssertTrue(app.otherElements["daily-card"].exists)
        XCTAssertFalse(app.textFields["Email"].exists)
        for _ in 0..<2 {
            XCTAssertTrue(share.isEnabled)
            XCTAssertTrue(share.isHittable)
            share.tap()
            let sheet = app.otherElements["ActivityListView"]
            XCTAssertTrue(sheet.waitForExistence(timeout: 10), "System share sheet must be presented.")
            if rotateWhilePresented {
                currentOrientation = currentOrientation == .portrait ? .landscapeLeft : .portrait
                XCUIDevice.shared.orientation = currentOrientation
                let landscape = currentOrientation == .landscapeLeft
                let rotated = NSPredicate { _, _ in
                    let frame = self.app.windows.firstMatch.frame
                    return landscape ? frame.width > frame.height : frame.height > frame.width
                }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: rotated, object: nil)], timeout: 10), .completed)
            }
            // Remote share UI can exist before its entrance animation/layout settles.
            var previousFrame = CGRect.null
            let settled = NSPredicate { _, _ in
                let frame = sheet.frame
                defer { previousFrame = frame }
                return !frame.isEmpty && self.app.windows.firstMatch.frame.contains(frame) && frame == previousFrame
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 10), .completed)
            let close = app.buttons["Close"].firstMatch
            let compactPortrait = UIDevice.current.userInterfaceIdiom == .phone && currentOrientation == .portrait
            if UIDevice.current.userInterfaceIdiom == .phone && !compactPortrait {
                XCTAssertTrue(close.waitForExistence(timeout: 10), "The expanded phone sheet must offer Close.")
            }
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Daily card system share sheet"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            if UIDevice.current.userInterfaceIdiom == .pad {
                // The popover is anchored to the upper-right Share button.
                let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
                XCTAssertFalse(sheet.frame.contains(outside.screenPoint))
                outside.tap()
            } else if compactPortrait {
                // The compact system card exposes the presenting surface for dismissal.
                let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.25))
                XCTAssertFalse(sheet.frame.contains(outside.screenPoint))
                outside.tap()
            } else {
                close.tap()
            }
            let usable = NSPredicate { _, _ in share.exists && share.isEnabled && share.isHittable }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: usable, object: nil)], timeout: 10), .completed)
            XCTAssertFalse(sheet.exists)
            XCTAssertFalse(app.alerts["Couldn't Share Card"].exists)
            XCTAssertTrue(app.otherElements["daily-card"].exists)
            if rotateWhilePresented { checkQuoteRemainsReachable() }
        }
        app.buttons["Settings"].tap()
        let signIn = app.buttons["Sign In"]
        // Native menu rows scroll at accessibility sizes in compact landscape.
        let menu = app.collectionViews.firstMatch
        for _ in 0..<4 where !signIn.exists || !signIn.isHittable {
            guard menu.exists else { break }
            menu.swipeUp()
        }
        XCTAssertTrue(signIn.waitForExistence(timeout: 5), "Use a dedicated guest QA simulator.")
        XCTAssertTrue(signIn.isHittable)
        // No destination is selected, no account request is submitted, and no card is sent.
    }
}

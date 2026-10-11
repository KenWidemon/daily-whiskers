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
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 5), "Use a dedicated guest QA simulator.")
        // No destination is selected, no account request is submitted, and no card is sent.
    }
}

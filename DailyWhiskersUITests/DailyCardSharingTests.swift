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
            let screenshot = XCTAttachment(screenshot: app.screenshot())
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

    private func tapInForm(_ element: XCUIElement) {
        let form = app.scrollViews["auth-form"]
        for _ in 0..<8 where !element.isHittable { form.swipeUp() }
        XCTAssertTrue(element.isHittable)
        element.tap()
    }

    private func checkCancellation(orientation: UIDeviceOrientation, textSize: UIContentSizeCategory) {
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
            // Remote share UI can exist before its entrance animation/layout settles.
            var previousFrame = CGRect.null
            let settled = NSPredicate { _, _ in
                let frame = sheet.frame
                defer { previousFrame = frame }
                return !frame.isEmpty && self.app.windows.firstMatch.frame.contains(frame) && frame == previousFrame
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 10), .completed)
            let close = app.buttons["Close"].firstMatch
            let compactPortrait = UIDevice.current.userInterfaceIdiom == .phone && orientation == .portrait
            if UIDevice.current.userInterfaceIdiom == .phone && !compactPortrait {
                XCTAssertTrue(close.waitForExistence(timeout: 10), "The expanded phone sheet must offer Close.")
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
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
        }
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 5), "Use a dedicated guest QA simulator.")
        // No destination is selected, no account request is submitted, and no card is sent.
    }
}

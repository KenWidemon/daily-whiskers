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
        if testRun?.hasSucceeded == false {
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
            let close = app.buttons["Close"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 10), "System share sheet must offer dismissal.")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Daily card system share sheet"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            close.tap()
            let usable = NSPredicate { _, _ in share.exists && share.isEnabled && share.isHittable }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: usable, object: nil)], timeout: 10), .completed)
            XCTAssertFalse(app.alerts["Couldn't Share Card"].exists)
            XCTAssertTrue(app.otherElements["daily-card"].exists)
        }
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 5), "Use a dedicated guest QA simulator.")
        // No destination is selected, no account request is submitted, and no card is sent.
    }
}

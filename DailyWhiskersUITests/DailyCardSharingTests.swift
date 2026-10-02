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

    private func checkCancellation(orientation: UIDeviceOrientation, textSize: UIContentSizeCategory) {
        XCUIDevice.shared.orientation = orientation
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", textSize.rawValue]
        app.launch()
        let share = app.buttons["share-daily-card"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertEqual(share.label, "Share Today's Card")
        XCTAssertTrue(app.otherElements["daily-card"].exists)
        XCTAssertFalse(app.textFields["Email"].exists)
        for attempt in 0..<2 {
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
            if !compactPortrait {
                XCTAssertTrue(close.waitForExistence(timeout: 10), "Expanded sheets/popovers must offer Close.")
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Daily card system share sheet"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            if UIDevice.current.userInterfaceIdiom == .pad && attempt == 1 {
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

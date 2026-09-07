import XCTest
import UIKit

@MainActor
final class AuthLayoutTests: XCTestCase {
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

    func testPortraitKeyboardNavigation() {
        launch(orientation: .portrait, textSize: .large)
        app.textFields["Email"].tap()
        let next = app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", "next")).firstMatch
        waitForVisibleKey(next)
        next.tap()
        let done = app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", "done")).firstMatch
        waitForVisibleKey(done)
        done.tap()
        // Empty fields must not authenticate or leave the login screen.
        XCTAssertTrue(app.textFields["Email"].exists)
        XCTAssertFalse(app.buttons["Sign In"].isEnabled)
        XCTAssertFalse(app.buttons["Create Account"].isEnabled)
    }

    func testLandscapeKeyboardScrolling() {
        checkScrolling(textSize: .large)
    }

    func testLandscapeAccessibilityKeyboardScrolling() {
        checkScrolling(textSize: .accessibilityExtraExtraExtraLarge)
    }

    private func launch(orientation: UIDeviceOrientation, textSize: UIContentSizeCategory) {
        XCUIDevice.shared.orientation = orientation
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", textSize.rawValue]
        app.launch()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 10),
                      "Run this scheme on a signed-out QA simulator. It never signs out a user.")
    }

    private func checkScrolling(textSize: UIContentSizeCategory) {
        launch(orientation: .landscapeLeft, textSize: textSize)
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists)
        let password = app.secureTextFields["Password"]
        for _ in 0..<6 where !password.isHittable {
            scroll.swipeUp()
        }
        XCTAssertTrue(password.isHittable)
        password.tap()
        let done = app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", "done")).firstMatch
        waitForVisibleKey(done)

        let createAccount = app.buttons["Create Account"]
        for _ in 0..<8 {
            if isFullyVisible(createAccount) { break }
            swipeVisibleContentUp(scroll)
        }
        XCTAssertTrue(isFullyVisible(createAccount),
                      "Create Account must be reachable when scrolling starts with the keyboard open.")
        // Interactive scrolling is allowed to dismiss the keyboard by design.
        XCTAssertFalse(createAccount.isEnabled)
    }

    private func isFullyVisible(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        let window = app.windows.firstMatch.frame
        return frame.width > 0 && frame.height > 0
            && element.isHittable
            && frame.minY >= window.minY && frame.maxY <= window.maxY
            && frame.minX >= window.minX && frame.maxX <= window.maxX
    }

    private func waitForVisibleKey(_ key: XCUIElement) {
        let visible = NSPredicate { [self] _, _ in
            guard key.exists, key.isHittable else { return false }
            return app.windows.firstMatch.frame.contains(key.frame)
        }
        let ready = XCTNSPredicateExpectation(predicate: visible, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed,
                       "Show the software keyboard on the QA simulator; an offscreen keyboard is not a valid test.")
    }

    private func swipeVisibleContentUp(_ scroll: XCUIElement) {
        // Use the upper form area, not the default swipe that starts behind the
        // docked keyboard. Keyboard container frames can include offscreen views.
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}

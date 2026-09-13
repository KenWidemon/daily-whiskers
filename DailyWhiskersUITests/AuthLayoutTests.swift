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
        XCTAssertFalse(app.buttons["Hide Keyboard"].exists,
                       "The extra keyboard toolbar action was removed by product request.")
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

    func testRepeatedLocalValidationErrorIsVisible() {
        launch(orientation: .portrait, textSize: .large)
        let reset = app.buttons["Forgot password?"]
        let error = app.staticTexts["Enter a valid email address."]

        for _ in 0..<2 {
            reset.tap()
            let visible = NSPredicate { [self] _, _ in isFullyVisible(error) }
            let ready = XCTNSPredicateExpectation(predicate: visible, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
            XCTAssertFalse(app.alerts["Check Your Email"].exists)
        }
        // This checks layout/repeated presentation, not VoiceOver speech or focus.
        XCTAssertFalse(app.buttons["Sign In"].isEnabled)
        XCTAssertFalse(app.buttons["Create Account"].isEnabled)
    }

    func testLandscapeAccessibilityKeyboardScrolling() {
        checkScrolling(textSize: .accessibilityExtraExtraExtraLarge)
    }

    func testGuestCanDismissAndReopenOptionalSignIn() {
        launch(orientation: .portrait, textSize: .large)
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("unfinished@example.com")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Email"].exists)

        openOptionalSignIn()
        XCTAssertEqual(app.textFields["Email"].value as? String, "Email",
                       "Dismissing optional auth must discard unfinished credentials.")
        app.buttons["Close"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["daily-card"].exists)
        XCTAssertFalse(app.textFields["Email"].exists,
                       "Relaunching as a guest must not require authentication.")
    }

    private func launch(orientation: UIDeviceOrientation, textSize: UIContentSizeCategory) {
        XCUIDevice.shared.orientation = orientation
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", textSize.rawValue]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["daily-card"].exists)
        XCTAssertFalse(app.textFields["Email"].exists,
                       "The daily card must open without a sign-in gate.")
        openOptionalSignIn()
    }

    private func openOptionalSignIn() {
        app.buttons["Settings"].tap()
        let signIn = app.buttons["Sign In"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10),
                      "Run on a signed-out QA simulator; this test never signs out a user.")
        XCTAssertFalse(app.buttons["Log Out"].exists)
        XCTAssertFalse(app.buttons["Delete Account"].exists)
        signIn.tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 10),
                      "Settings must open optional authentication.")
    }

    private func checkScrolling(textSize: UIContentSizeCategory) {
        launch(orientation: .landscapeLeft, textSize: textSize)
        let scroll = app.scrollViews["auth-form"]
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

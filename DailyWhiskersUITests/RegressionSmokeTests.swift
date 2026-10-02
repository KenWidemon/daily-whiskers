import XCTest

final class RegressionSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ci-smoke", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ci-smoke-offline"].waitForExistence(timeout: 10), "Requires the isolated CI Debug build.")
        XCTAssertTrue(app.otherElements["daily-card"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testGuestDailyContentAndRelaunch() {
        XCTAssertFalse(app.staticTexts["No daily content found."].exists)
        XCTAssertFalse(app.textFields["Email"].exists)
        XCTAssertTrue(app.buttons["Settings"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.otherElements["daily-card"].waitForExistence(timeout: 10))
    }

    func testAccountToolsOpenAndDismiss() {
        openSignIn()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["auth-form"].exists)
        openSignIn()
    }

    func testLocalAuthValidationAndRegistrationNavigation() {
        openSignIn()
        XCTAssertFalse(app.buttons["Sign In"].isEnabled)
        app.buttons["Forgot password?"].tap()
        XCTAssertTrue(app.staticTexts["Enter a valid email address."].waitForExistence(timeout: 5))
        tapInForm(app.buttons["Create Account"])
        XCTAssertTrue(app.textFields["registration-email"].waitForExistence(timeout: 5))
        tapInForm(app.buttons["registration-submit"])
        XCTAssertTrue(app.staticTexts["Enter a valid email address."].waitForExistence(timeout: 5))
        tapInForm(app.buttons["Back to Sign In"])
        XCTAssertTrue(app.buttons["Forgot password?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["registration-submit"].exists)
    }

    private func openSignIn() {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Log Out"].exists)
        XCTAssertFalse(app.buttons["Delete Account"].exists)
        app.buttons["Sign In"].tap()
        XCTAssertTrue(app.scrollViews["auth-form"].waitForExistence(timeout: 5))
    }

    private func tapInForm(_ element: XCUIElement) {
        let scroll = app.scrollViews["auth-form"]
        for _ in 0..<6 where !element.isHittable { scroll.swipeUp() }
        XCTAssertTrue(element.isHittable)
        element.tap()
    }
}

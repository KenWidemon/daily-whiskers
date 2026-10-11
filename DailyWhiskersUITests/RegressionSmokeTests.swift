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

    func testRegistrationEditingAfterBackCloseAndProcessRelaunch() {
        openSignIn()
        for attempt in 0..<4 {
            tapInForm(app.buttons["Create Account"])
            let email = app.textFields["registration-email"]
            let password = app.secureTextFields["registration-password"]
            XCTAssertTrue(email.waitForExistence(timeout: 5))
            XCTAssertEqual(email.value as? String, "Email")
            XCTAssertEqual(password.value as? String, "Empty")
            XCTAssertFalse(app.secureTextFields["registration-confirmation"].exists)
            tapInForm(email)
            email.typeText("repeat@example.invalid")
            tapInForm(password)
            password.typeText("Synthetic-Repeat-1")
            tapInForm(email)
            tapInForm(password)
            XCTAssertEqual(password.value as? String, "Password entered")
            // These are ordinary synthetic edits through production controls.
            // They do not establish password-provider or strong-password success.
            switch attempt {
            case 0:
                tapInForm(app.buttons["Back to Sign In"])
                XCTAssertTrue(app.buttons["Forgot password?"].waitForExistence(timeout: 5))
                XCTAssertEqual(app.secureTextFields["sign-in-password"].value as? String, "Empty")
            case 1:
                app.buttons["Close"].tap()
                XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
                openSignIn()
            case 2:
                app.terminate()
                app.launch()
                XCTAssertTrue(app.otherElements["daily-card"].waitForExistence(timeout: 10))
                openSignIn()
            default:
                app.buttons["Close"].tap()
            }
        }
        // Never submits a registration or invokes a live authentication service.
    }

    func testSinglePasswordDoneReachesOnlyOfflineBoundary() {
        openSignIn()
        tapInForm(app.buttons["Create Account"])
        let email = app.textFields["registration-email"]
        let password = app.secureTextFields["registration-password"]
        tapInForm(email)
        email.typeText("single@example.invalid")
        tapInForm(password)
        password.typeText("Synthetic-Single-1")
        XCTAssertFalse(app.secureTextFields["registration-confirmation"].exists)
        XCTAssertFalse(app.textFields["registration-confirmation"].exists)
        XCTAssertFalse(app.buttons["Show Confirm Password"].exists)
        let done = app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", "done")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        done.tap()
        // setUp requires the offline marker before interacting. A valid form
        // reaches the existing fail-closed seam, never Firebase or fake success.
        XCTAssertTrue(app.staticTexts["Something went wrong. Please try again."].waitForExistence(timeout: 5))
        XCTAssertEqual(password.value as? String, "Password entered")
        XCTAssertTrue(app.buttons["registration-submit"].isEnabled)
        tapInForm(app.buttons["Back to Sign In"])
        XCTAssertTrue(app.buttons["Forgot password?"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.secureTextFields["sign-in-password"].value as? String, "Empty")
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
        for _ in 0..<6 where !element.isHittable {
            // The default swipe can begin behind the docked keyboard and never
            // scroll the form. Keep the gesture in its upper visible content.
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
        element.tap()
    }
}

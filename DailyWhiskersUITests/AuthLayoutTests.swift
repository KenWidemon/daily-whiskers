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
        XCTAssertTrue(app.buttons["Create Account"].isEnabled)
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
        XCTAssertTrue(app.buttons["Create Account"].isEnabled)
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

    func testSignInVisibilityEditingAndLifecycle() {
        launch(orientation: .portrait, textSize: .large)
        let show = app.buttons["Show Password"]
        let hide = app.buttons["Hide Password"]
        XCTAssertTrue(app.secureTextFields["sign-in-password"].exists)
        XCTAssertEqual(show.value as? String, "Hidden")
        show.tap()
        XCTAssertEqual(hide.value as? String, "Visible")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        hide.tap()

        let email = app.textFields["sign-in-email"]
        email.tap()
        email.typeText("validation@example.com")
        let password = app.secureTextFields["sign-in-password"]
        password.tap()
        password.typeText("abc")
        XCTAssertFalse(app.buttons["Sign In"].isEnabled)
        show.tap()
        XCTAssertEqual(app.textFields["sign-in-password"].value as? String, "Password entered")
        waitForVisibleKey(app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", "done")).firstMatch)
        // Send keys to the current responder without tapping/refocusing the field.
        app.typeText("de")
        hide.tap()
        app.typeText("f")
        XCTAssertTrue(app.buttons["Sign In"].isEnabled,
                      "Visibility changes must retain editing; existing six-character passwords remain eligible.")
        XCTAssertTrue(app.buttons["Forgot password?"].isEnabled)
        XCTAssertTrue(app.buttons["Create Account"].isEnabled)
        show.tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        XCTAssertTrue(password.exists)
        XCTAssertTrue(app.buttons["Sign In"].isEnabled)

        show.tap()
        app.buttons["Create Account"].tap()
        app.buttons["Back to Sign In"].tap()
        XCTAssertTrue(show.exists)
        XCTAssertEqual(password.value as? String, "Empty")
        XCTAssertFalse(app.buttons["Sign In"].isEnabled)
        password.tap()
        password.typeText("discard-me")
        show.tap()
        app.buttons["Close"].tap()
        openOptionalSignIn()
        XCTAssertTrue(show.exists)
        XCTAssertEqual(password.value as? String, "Empty")
        XCTAssertEqual(email.value as? String, "Email")
        XCTAssertFalse(app.buttons["Sign In"].isEnabled)
        // No Sign In, reset or registration submission occurs in this test.
    }

    func testSignInVisibilityLargeText() {
        launch(orientation: .portrait, textSize: .accessibilityExtraExtraExtraLarge)
        let scroll = app.scrollViews["auth-form"]
        let show = app.buttons["Show Password"]
        for _ in 0..<12 where !isFullyVisible(show) { scroll.swipeUp() }
        XCTAssertTrue(isFullyVisible(show))
        XCTAssertGreaterThanOrEqual(show.frame.width, 44)
        XCTAssertGreaterThanOrEqual(show.frame.height, 44)
        show.tap()
        XCTAssertTrue(app.buttons["Hide Password"].isHittable)
        app.buttons["Hide Password"].tap()
        XCTAssertTrue(app.secureTextFields["sign-in-password"].exists)
    }

    func testRegistrationMaskedRefocusAfterVisibilityToggle() {
        registrationMaskedRefocus(populateEmail: true)
    }

    func testRegistrationMaskedRefocusWithoutEmail() {
        registrationMaskedRefocus(populateEmail: false)
    }

    func testRegistrationEmptyEmailFocusedFirst() {
        registrationMaskedRefocus(populateEmail: false, focusEmailFirst: true)
    }

    func testRegistrationEmptyEmailWithoutInitialToggle() {
        registrationMaskedRefocus(populateEmail: false, initialToggle: false)
    }

    private func registrationMaskedRefocus(populateEmail: Bool, focusEmailFirst: Bool = false, initialToggle: Bool = true) {
        launch(orientation: .portrait, textSize: .large)
        app.buttons["Create Account"].tap()
        let email = app.textFields["registration-email"]
        let password = app.secureTextFields["registration-password"]
        let passwordInput = app.descendants(matching: .any)["registration-password"].firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        func capture(_ name: String) {
            print("DW86 capture: \(name)")
            fflush(stdout)
            // Allow the secure-entry render and SF Symbol transition to settle.
            Thread.sleep(forTimeInterval: 4)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = name + " hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        if populateEmail {
            email.tap()
            email.typeText("refocus@example.invalid")
        } else {
            // The former disclosure sequence is now contained at its entry point.
            XCTAssertEqual(email.value as? String, "Email")
            XCTAssertFalse(password.isEnabled)
            XCTAssertFalse(app.buttons["Show Password"].isEnabled)
            XCTAssertTrue(app.staticTexts["registration-email-first"].exists)
            capture("Blank Email disables password and shows guidance")
            email.tap()
            email.typeText(" ")
            XCTAssertFalse(password.isEnabled, "Whitespace is still blank.")
            if focusEmailFirst {
                let next = app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", "next")).firstMatch
                waitForVisibleKey(next)
                next.tap()
                XCTAssertFalse(password.isEnabled)
                XCTAssertTrue(app.keyboards.keys["@"].exists, "Blank Email Next must keep the email keyboard.")
            }
            email.typeText(XCUIKeyboardKey.delete.rawValue + "x")
            XCTAssertTrue(password.isEnabled, "A nonblank partial address enables entry before validation.")
        }
        passwordInput.tap()
        password.typeText("Synthetic-Refocus-42")
        if initialToggle {
            app.buttons["Show Password"].tap()
            app.buttons["Hide Password"].tap()
        }
        capture(initialToggle ? "Initially explicitly masked" : "Initially masked without toggling")
        for round in 1...2 {
            email.tap()
            passwordInput.tap()
            capture("Refocus \(round) before touching Show")
            XCTAssertTrue(password.exists)
            XCTAssertEqual(app.buttons["Show Password"].value as? String, "Hidden")
            XCTAssertEqual(passwordInput.value as? String, "Password entered")
            app.buttons["Show Password"].tap()
            capture("Refocus \(round) after Show")
            XCTAssertTrue(app.textFields["registration-password"].exists)
            XCTAssertEqual(app.buttons["Hide Password"].value as? String, "Visible")
            app.buttons["Hide Password"].tap()
            capture("Refocus \(round) after Hide")
            XCTAssertTrue(password.exists)
        }
        // Clearing a revealed password's email must mask and retain the draft.
        app.buttons["Show Password"].tap()
        email.tap()
        let emailLength = populateEmail ? "refocus@example.invalid".count : 1
        email.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: emailLength))
        XCTAssertEqual(email.value as? String, "Email")
        XCTAssertFalse(passwordInput.isEnabled)
        XCTAssertFalse(app.buttons["Show Password"].isEnabled)
        XCTAssertTrue(app.staticTexts["registration-email-first"].exists)
        XCTAssertTrue(password.exists)
        XCTAssertEqual(password.value as? String, "Password entered")
        capture("Cleared email retains masked password and disables controls")
        email.typeText(" ")
        XCTAssertFalse(passwordInput.isEnabled)
        XCTAssertTrue(password.exists)
        email.typeText(XCUIKeyboardKey.delete.rawValue + "x")
        XCTAssertTrue(passwordInput.isEnabled)
        let next = app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", "next")).firstMatch
        waitForVisibleKey(next)
        next.tap()
        XCTAssertTrue(password.exists)
        capture("Restored nonblank email remains masked before Show")
        app.buttons["Show Password"].tap()
        capture("Restored email Show reveals retained synthetic input")
        app.buttons["Hide Password"].tap()
        // Deliberate deletion/retyping must remain possible after the gate reopens.
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Synthetic-Refocus-42".count))
        XCTAssertEqual(password.value as? String, "Empty")
        app.typeText("Retyped-Synthetic-7")
        app.buttons["Show Password"].tap()
        capture("Deliberately retyped synthetic input after restoration")
        app.buttons["Hide Password"].tap()
        XCTAssertTrue(password.exists)
        // Synthetic input only; never submits registration.
    }

    func testRegistrationNavigationAndCredentialIsolation() {
        launch(orientation: .portrait, textSize: .large)
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("prefill@")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("discard-me")
        app.buttons["Create Account"].tap()
        XCTAssertTrue(app.buttons["registration-submit"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["registration-email"].value as? String, "prefill@")
        XCTAssertEqual(app.secureTextFields["registration-password"].value as? String, "Empty")
        XCTAssertFalse(app.secureTextFields["registration-confirmation"].exists)
        app.buttons["Back to Sign In"].tap()
        XCTAssertTrue(app.buttons["Forgot password?"].exists)
        XCTAssertFalse(app.buttons["Sign In"].isEnabled)
        XCTAssertEqual(app.secureTextFields["Password"].value as? String, "Empty")
        app.buttons["Create Account"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.otherElements["daily-card"].exists)
        openOptionalSignIn()
        XCTAssertEqual(app.textFields["Email"].value as? String, "Email")
    }

    func testRegistrationValidationAndVisibility() {
        launch(orientation: .portrait, textSize: .large)
        app.buttons["Create Account"].tap()
        let submit = app.buttons["registration-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Dedicated Create Account"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        submit.tap()
        XCTAssertTrue(app.staticTexts["Enter a valid email address."].waitForExistence(timeout: 5))
        let email = app.textFields["registration-email"]
        email.tap()
        email.typeText("validation@example.com")
        let password = app.secureTextFields["registration-password"]
        password.tap()
        password.typeText("short")
        app.buttons["Show Password"].tap()
        XCTAssertTrue(app.textFields["registration-password"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["Hide Password"].exists)
        app.buttons["Hide Password"].tap()
        XCTAssertTrue(app.secureTextFields["registration-password"].exists)
        submit.tap()
        XCTAssertTrue(app.staticTexts["Use at least 8 characters for your password."].waitForExistence(timeout: 5))
        password.tap()
        password.typeText("er1")
        submit.tap()
        XCTAssertTrue(app.staticTexts["Add an uppercase letter (A–Z) to your password."].waitForExistence(timeout: 5))
        password.tap()
        password.typeText("A")
        submit.tap()
        // This is now a valid single-password form. launch() requires the
        // offline boundary so the submit cannot create a real account.
        XCTAssertTrue(app.staticTexts["Something went wrong. Please try again."].waitForExistence(timeout: 5))
        app.buttons["Show Password"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Show Password"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["registration-password"].exists)
        app.buttons["Back to Sign In"].tap()
        app.buttons["Create Account"].tap()
        XCTAssertEqual(app.secureTextFields["registration-password"].value as? String, "Empty")
    }

    func testRegistrationPasswordPrivacyAndCloseDiscard() {
        launch(orientation: .portrait, textSize: .large)
        app.buttons["Create Account"].tap()
        app.textFields["registration-email"].tap()
        app.textFields["registration-email"].typeText("x")
        let password = app.secureTextFields["registration-password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("Synthetic1")
        app.buttons["Show Password"].tap()
        XCTAssertEqual(app.textFields["registration-password"].value as? String, "Password entered")
        XCTAssertFalse(app.textFields["registration-confirmation"].exists)
        XCTAssertFalse(app.buttons["Show Confirm Password"].exists)
        app.typeText("x")
        app.buttons["Hide Password"].tap()
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(password.value as? String, "Password entered")
        app.buttons["Show Password"].tap()

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Show Password"].waitForExistence(timeout: 5))
        XCTAssertEqual(password.value as? String, "Password entered")

        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        openOptionalSignIn()
        app.buttons["Create Account"].tap()
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        XCTAssertEqual(password.value as? String, "Empty")
        XCTAssertTrue(app.buttons["Show Password"].exists)
        // No submission: this checks simulator lifecycle and accessibility values,
        // not VoiceOver speech or exact input (covered by native-field unit tests).
    }

    func testSwipeDismissalDiscardsSignInAndRegistrationDrafts() {
        launch(orientation: .portrait, textSize: .large)
        for registration in [false, true] {
            if registration {
                app.buttons["Create Account"].tap()
                app.textFields["registration-email"].tap()
                app.textFields["registration-email"].typeText("x")
            }
            let identifier = registration ? "registration-password" : "sign-in-password"
            let password = app.secureTextFields[identifier]
            XCTAssertTrue(password.waitForExistence(timeout: 5))
            password.tap()
            password.typeText("discard-me")
            app.buttons["Show Password"].tap()

            // The daily card's bar also remains in the phone hierarchy. Target
            // the sheet by Close, then drag far enough to dismiss the sheet.
            let sheetBar = app.navigationBars.containing(.button, identifier: "Close").firstMatch
            XCTAssertTrue(sheetBar.exists)
            let start = sheetBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            start.press(forDuration: 0.05, thenDragTo: end)
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                      object: app.buttons["Close"])
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Close"].exists)
            openOptionalSignIn()
            XCTAssertEqual(app.secureTextFields["sign-in-password"].value as? String, "Empty")
            if registration {
                app.buttons["Create Account"].tap()
                XCTAssertTrue(password.waitForExistence(timeout: 5))
                XCTAssertEqual(password.value as? String, "Empty")
                XCTAssertFalse(app.secureTextFields["registration-confirmation"].exists)
            }
            XCTAssertTrue(app.buttons["Show Password"].exists)
        }
    }

    func testRegistrationLargeTextScrolling() {
        launch(orientation: .portrait, textSize: .accessibilityExtraExtraExtraLarge)
        let scroll = app.scrollViews["auth-form"]
        let open = app.buttons["Create Account"]
        for _ in 0..<12 where !open.isHittable { scroll.swipeUp() }
        open.tap()
        XCTAssertTrue(app.buttons["registration-submit"].waitForExistence(timeout: 5))
        let email = app.textFields["registration-email"]
        for _ in 0..<12 where !email.isHittable { scroll.swipeUp() }
        email.tap()
        email.typeText("x")
        let password = app.secureTextFields["registration-password"]
        for _ in 0..<12 where !password.isHittable { scroll.swipeUp() }
        password.tap()
        waitForVisibleKey(app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", "done")).firstMatch)
        let submit = app.buttons["registration-submit"]
        for _ in 0..<12 where !isFullyVisible(submit) { swipeVisibleContentUp(scroll) }
        XCTAssertTrue(isFullyVisible(submit))
        let back = app.buttons["Back to Sign In"]
        for _ in 0..<12 where !isFullyVisible(back) { swipeVisibleContentUp(scroll) }
        XCTAssertTrue(isFullyVisible(back))
        back.tap()
        XCTAssertTrue(app.buttons["Forgot password?"].exists)
    }

    private func launch(orientation: UIDeviceOrientation, textSize: UIContentSizeCategory) {
        XCUIDevice.shared.orientation = orientation
        app.launchArguments = ["--ci-smoke", "-UIPreferredContentSizeCategoryName", textSize.rawValue]
        app.launch()
        XCTAssertTrue(app.staticTexts["ci-smoke-offline"].waitForExistence(timeout: 10),
                      "Requires DEBUG + CI_SMOKE_TESTING; never interact without the offline boundary.")
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["daily-card"].exists)
        XCTAssertFalse(app.textFields["Email"].exists,
                       "The daily card must open without a sign-in gate.")
        openOptionalSignIn()
    }

    private func openOptionalSignIn() {
        app.buttons["Settings"].tap()
        let signIn = app.buttons["Sign In"]
        // Native menu rows scroll at accessibility sizes in compact landscape.
        let menu = app.collectionViews.firstMatch
        for _ in 0..<4 where !signIn.exists || !signIn.isHittable {
            guard menu.exists else { break }
            menu.swipeUp()
        }
        XCTAssertTrue(signIn.waitForExistence(timeout: 10),
                      "Run on a signed-out QA simulator; this test never signs out a user.")
        XCTAssertTrue(signIn.isHittable)
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
        XCTAssertTrue(createAccount.isEnabled)
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
            // UIKit can round an edge key's accessibility frame half a point
            // beyond the display. Keep the visible, hittable-key precondition
            // while allowing that rounding; offscreen keyboards still fail.
            return app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(key.frame)
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

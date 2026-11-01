import XCTest

/// Offline UI decisions only. ReminderSmokeClient has no UN notification center
/// access, so these tests never request system permission or deliver alerts.
final class ReminderUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ci-smoke", "--ci-smoke-reminders", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["DW_REMINDER_TEST_ID"] = UUID().uuidString
    }
    override func tearDown() { app.terminate() }

    private func openSettings() {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let reminder = app.buttons["open-daily-reminder"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5)); reminder.tap()
        XCTAssertTrue(app.switches["reminder-enabled"].waitForExistence(timeout: 5))
        waitEnabled(app.switches["reminder-enabled"])
    }
    private func waitEnabled(_ control: XCUIElement) {
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 15), .completed)
    }
    private func waitValue(_ control: XCUIElement, _ value: String) {
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 15), .completed)
    }
    private func tapToggle(_ control: XCUIElement) {
        // SwiftUI exposes a labeled row and its native switch. Tap the switch,
        // not the noninteractive center of the label's full-width frame.
        let native = control.switches.firstMatch
        XCTAssertTrue(native.exists); native.tap()
    }
    private func reveal(_ control: XCUIElement) {
        for _ in 0..<6 { if control.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(control.isHittable)
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + " accessibility"; tree.lifetime = .keepAlways; add(tree)
    }

    private func editDraftTime(hour: String, minute: String) {
        let picker = app.datePickers["reminder-time-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["Time Picker"].tap()
        capture("Native reminder time picker opened")
        let hourWheel = app.pickerWheels.element(boundBy: 0)
        XCTAssertTrue(hourWheel.waitForExistence(timeout: 5))
        hourWheel.adjust(toPickerWheelValue: hour)
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: minute)
        app.buttons["PopoverDismissRegion"].tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: hourWheel)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
    }

    private func waitTime(_ value: String) {
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", value), object: app.buttons["reminder-time"])
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 10), .completed)
    }

    func testDefaultOffTimeSaveCancelAndRelaunch() {
        app.launch(); openSettings()
        let toggle = app.switches["reminder-enabled"]
        waitValue(toggle, "0")
        XCTAssertTrue(app.staticTexts["reminder-permission"].label.contains("only when you turn"))
        app.buttons["reminder-time"].tap()
        XCTAssertTrue(app.buttons["reminder-time-cancel"].waitForExistence(timeout: 5))
        editDraftTime(hour: "11", minute: "30")
        app.buttons["reminder-time-cancel"].tap()
        waitValue(toggle, "0")
        waitTime("9:00")
        app.buttons["reminder-time"].tap()
        XCTAssertTrue(app.buttons["reminder-time-save"].waitForExistence(timeout: 5))
        editDraftTime(hour: "10", minute: "15")
        app.buttons["reminder-time-save"].tap()
        waitValue(toggle, "0")
        waitTime("10:15")
        capture("Reminder off after saving time")
        app.terminate(); app.launch(); openSettings()
        waitValue(app.switches["reminder-enabled"], "0")
        waitTime("10:15")
        XCTAssertTrue(app.staticTexts["reminder-permission"].label.contains("only when you turn"))
    }

    func testPermissionRevocationRegrantAndExplicitDisable() {
        app.launch(); openSettings()
        let toggle = app.switches["reminder-enabled"]
        tapToggle(toggle); waitValue(toggle, "1"); waitEnabled(toggle)
        XCTAssertEqual(app.staticTexts["reminder-permission"].label, "Notifications allowed.")
        let revoke = app.buttons["sheet-reminder-test-revoke"]
        reveal(revoke); revoke.tap()
        let blocked = app.staticTexts["reminder-permission"]
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Blocked in iOS Settings'"), object: blocked)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 10), .completed)
        let regrant = app.buttons["sheet-reminder-test-regrant"]
        reveal(regrant); regrant.tap()
        let allowed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Notifications allowed.'"), object: blocked)
        XCTAssertEqual(XCTWaiter.wait(for: [allowed], timeout: 10), .completed)
        for _ in 0..<6 { if toggle.isHittable { break }; app.swipeDown() }
        waitEnabled(toggle); tapToggle(toggle); waitValue(toggle, "0"); waitEnabled(toggle)
        reveal(revoke); revoke.tap(); reveal(regrant); regrant.tap()
        for _ in 0..<6 { if toggle.isHittable { break }; app.swipeDown() }
        waitValue(toggle, "0")
        capture("Reminder disabled after permission regrant")
    }

    func testOldReminderRoutesFromSavedAndBonusToCurrentToday() {
        app.launch()
        XCTAssertTrue(app.buttons["open-saved-cards"].waitForExistence(timeout: 10))
        app.buttons["open-saved-cards"].tap()
        XCTAssertTrue(app.navigationBars["Saved Cards"].waitForExistence(timeout: 10))
        app.buttons["root-reminder-test-tap"].tap()
        XCTAssertTrue(app.buttons["card-menu"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["card-menu"].label, "Today, Card Menu")
        app.buttons["card-menu"].tap()
        let bonus = app.buttons["Open Bonus Card"]
        XCTAssertTrue(bonus.waitForExistence(timeout: 5)); bonus.tap()
        let bonusWait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Bonus Card, Card Menu'"), object: app.buttons["card-menu"])
        XCTAssertEqual(XCTWaiter.wait(for: [bonusWait], timeout: 10), .completed)
        app.buttons["root-reminder-test-tap"].tap()
        XCTAssertEqual(app.buttons["card-menu"].label, "Today, Card Menu")
        capture("Reminder returned to Today")
    }

    func testOldReminderDismissesNestedTimeEditorAndColdLaunchOpensToday() {
        app.launch(); openSettings()
        app.buttons["reminder-time"].tap()
        XCTAssertTrue(app.buttons["reminder-time-save"].waitForExistence(timeout: 5))
        app.buttons["editor-reminder-test-tap"].tap()
        XCTAssertTrue(app.buttons["card-menu"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["reminder-time-save"].exists)
        XCTAssertEqual(app.buttons["card-menu"].label, "Today, Card Menu")
        app.terminate(); app.launchArguments.append("--ci-smoke-reminder-cold-tap"); app.launch()
        XCTAssertTrue(app.buttons["card-menu"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["card-menu"].label, "Today, Card Menu")
    }

    func testLargestTextSettingsAndTimeControlsRemainReachable() {
        app.launchArguments.removeAll { $0 == "--ci-smoke-reminders" }
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); openSettings()
        let time = app.buttons["reminder-time"]
        reveal(time)
        XCTAssertGreaterThanOrEqual(time.frame.height, 44)
        capture("Reminder settings largest text")
        time.tap()
        XCTAssertTrue(app.buttons["reminder-time-save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reminder-time-cancel"].isHittable)
        XCTAssertTrue(app.buttons["reminder-time-save"].isHittable)
        capture("Reminder time largest text")
    }

    func testReminderDismissesSavedDetailSystemShareWithoutDeletingCard() {
        app.launchArguments.append("--ci-smoke-reminder-tap-after-share")
        app.launch()
        let options = app.buttons["daily-card-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 10)); waitEnabled(options)
        if options.value as? String != "Saved" { app.toggleDailyCardSave() }
        app.buttons["open-saved-cards"].tap()
        let row = app.buttons["saved-card-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let detail = app.buttons["saved-card-options"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10)); detail.tap()
        let share = app.buttons["saved-card-share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5)); share.tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sheet)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 15), .completed)
        XCTAssertTrue(app.buttons["card-menu"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["card-menu"].label, "Today, Card Menu")
        app.buttons["open-saved-cards"].tap()
        XCTAssertTrue(app.buttons["saved-card-row"].firstMatch.waitForExistence(timeout: 10))
        capture("Saved card retained after reminder dismissed share")
    }
}

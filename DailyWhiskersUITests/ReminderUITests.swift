import XCTest

/// Offline UI decisions only. ReminderSmokeClient has no UN notification center
/// access, so these tests never request system permission or deliver alerts.
final class ReminderUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() { diagnosticTestEntered()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ci-smoke", "--ci-smoke-reminders", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["DW_REMINDER_TEST_ID"] = UUID().uuidString
    }
    override func tearDown() { diagnosticWillTerminate(); app.terminate(); diagnosticDidTerminate() }

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
        XCTAssertEqual(diagnosticWait(wait, control: control, expected: "enabled", timeout: 15), .completed)
    }
    private func waitValue(_ control: XCUIElement, _ value: String) {
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: control)
        XCTAssertEqual(diagnosticWait(wait, control: control, expected: value, timeout: 15), .completed)
    }
    private func tapToggle(_ control: XCUIElement) {
        // SwiftUI exposes a labeled row and its native switch. Tap the switch,
        // not the noninteractive center of the label's full-width frame.
        let native = control.switches.firstMatch
        XCTAssertTrue(native.exists); diagnosticTap(native)
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
        configureReminderDiagnostic(); app.launch(); openSettings()
        let toggle = app.switches["reminder-enabled"]
        tapToggle(toggle); waitValue(toggle, "1"); waitEnabled(toggle)
        XCTAssertEqual(app.staticTexts["reminder-permission"].label, "Notifications allowed.")
        let revoke = app.buttons["sheet-reminder-test-revoke"]
        reveal(revoke); revoke.tap()
        let blocked = app.staticTexts["reminder-permission"]
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Blocked in iOS Settings'"), object: blocked)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 10), .completed)
        XCTAssertEqual(blocked.label, "Blocked in iOS Settings. Your time and enabled preference are kept. Existing reminders may resume when permission returns. Reopen the app to check coverage.")
        let navigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(navigationBar.exists)
        for _ in 0..<6 {
            if blocked.isHittable && blocked.frame.minY >= navigationBar.frame.maxY { break }
            app.swipeDown()
        }
        XCTAssertTrue(blocked.isHittable)
        XCTAssertGreaterThanOrEqual(blocked.frame.minY, navigationBar.frame.maxY)
        XCTAssertLessThanOrEqual(blocked.frame.maxY, app.frame.maxY)
        capture("Reminder permission explains possible resume before reopening")
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

    func testDeniedTimeEditKeepsEnabledIntentAndExplainsMissingCoverage() {
        XCUIDevice.shared.orientation = .portrait
        let fixtureDay = Calendar.current.startOfDay(for: Date())
        app.launch(); openSettings()
        let toggle = app.switches["reminder-enabled"]
        tapToggle(toggle); waitValue(toggle, "1"); waitEnabled(toggle)
        let revoke = app.buttons["sheet-reminder-test-revoke"]
        reveal(revoke); revoke.tap()
        let permission = app.staticTexts["reminder-permission"]
        let denied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Blocked in iOS Settings'"), object: permission)
        XCTAssertEqual(XCTWaiter.wait(for: [denied], timeout: 10), .completed)
        let time = app.buttons["reminder-time"]
        for _ in 0..<6 { if time.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(time.isHittable); waitEnabled(time); time.tap()
        // Earlier than the default 9:00 time, so this edit cannot introduce
        // today's unreserved future target after the original time has passed.
        editDraftTime(hour: "8", minute: "15")
        let save = app.buttons["reminder-time-save"]
        save.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        waitTime("8:15")
        waitValue(toggle, "1"); waitEnabled(toggle)
        let regrant = app.buttons["sheet-reminder-test-regrant"]
        reveal(regrant); regrant.tap()
        let coverage = app.staticTexts["reminder-coverage-status"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 10))
        XCTAssertEqual(Calendar.current.startOfDay(for: Date()), fixtureDay,
                       "A civil-date rollover invalidates this zero-coverage fixture; it is not proof of a scheduling failure.")
        XCTAssertEqual(coverage.label, "No upcoming reminders are confirmed. Missing reminders may be skipped to avoid duplicates. Open the app again to check coverage.")
        for _ in 0..<6 { if coverage.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(coverage.isHittable)
        capture("Reminder missing coverage explains conservative suppression")
        for _ in 0..<6 { if toggle.isHittable { break }; app.swipeDown() }
        waitValue(toggle, "1")
        waitTime("8:15")
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

    func testReminderDismissesStillnessAndPreservesBothSettings() {
        app.launchEnvironment["DW_STILLNESS_TEST_ID"] = UUID().uuidString
        app.launch(); openSettings()
        waitValue(app.switches["reminder-enabled"], "0")
        app.buttons["reminder-done"].tap()
        app.buttons["Settings"].tap()
        let stillness = app.buttons["open-stillness"]
        XCTAssertTrue(stillness.waitForExistence(timeout: 5)); stillness.tap()
        let toggle = app.switches["stillness-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        waitValue(toggle, "0"); tapToggle(toggle); waitValue(toggle, "1")
        let reminderTap = app.buttons["stillness-reminder-test-tap"]
        XCTAssertTrue(reminderTap.isHittable); reminderTap.tap()
        XCTAssertTrue(app.buttons["card-menu"].waitForExistence(timeout: 10))
        XCTAssertFalse(toggle.exists)
        XCTAssertEqual(app.buttons["card-menu"].label, "Today, Card Menu")

        app.buttons["Settings"].tap(); app.buttons["open-stillness"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); waitValue(toggle, "1")
        app.buttons["Done"].tap(); openSettings()
        waitValue(app.switches["reminder-enabled"], "0")
        waitTime("9:00")
        capture("Reminder and Stillness retained after returning to Today")
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

    // Helpers remain below the original scenarios: the original failing
    // XCTAssertEqual stays at the same file/line and evaluates only one 15s wait.
    private func diagnosticWait(_ wait: XCTNSPredicateExpectation, control: XCUIElement,
                                expected: String, timeout: TimeInterval) -> XCTWaiter.Result {
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        let began = DispatchTime.now().uptimeNanoseconds
#endif
        let result = XCTWaiter.wait(for: [wait], timeout: timeout)
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        if diagnosticSelected {
            let ended = DispatchTime.now().uptimeNanoseconds
            var evidence: [String: Any] = [
                "event": "wait.return", "session_id": app.launchEnvironment["DW_REMINDER_TEST_ID"] ?? "missing",
                "wait_started_monotonic_ns": began, "wait_returned_monotonic_ns": ended,
                "wall_time_unix": Date().timeIntervalSince1970, "timeout_seconds": timeout,
                "completed": result == .completed, "expected": expected, "action_index": diagnosticTapIndex
            ]
            if result != .completed {
                // Read-only snapshots, no retry/tap/second wait, before XCTest's
                // original fatal assertion. Fixed categories exclude user data.
                let parentExists = control.exists
                let native = control.switches.firstMatch
                let nativeExists = parentExists && native.exists
                evidence["parent_exists"] = parentExists
                evidence["parent_value"] = parentExists ? diagnosticValue(control) : "absent"
                evidence["parent_enabled"] = parentExists && control.isEnabled
                evidence["parent_hittable"] = parentExists && control.isHittable
                evidence["native_exists"] = nativeExists
                evidence["native_value"] = nativeExists ? diagnosticValue(native) : "absent"
                evidence["native_enabled"] = nativeExists && native.isEnabled
                evidence["native_hittable"] = nativeExists && native.isHittable
                let error = app.staticTexts["reminder-error"]
                evidence["error_exists"] = error.exists
                evidence["error_category"] = diagnosticError(error)
                evidence["permission_status"] = diagnosticPermission(app.staticTexts["reminder-permission"])
                evidence["observation_completed_monotonic_ns"] = DispatchTime.now().uptimeNanoseconds
                diagnosticEvidence(evidence, attach: true)
                capture("Reminder diagnostic before original wait assertion")
            } else { diagnosticEvidence(evidence, attach: false) }
        }
#endif
        return result
    }

    private func diagnosticTap(_ native: XCUIElement) {
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        if diagnosticSelected { diagnosticTapIndex += 1 }
        let began = DispatchTime.now().uptimeNanoseconds
#endif
        native.tap() // Exactly the original single native tap, with no alternate path.
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        if diagnosticSelected {
            diagnosticEvidence(["event": "native_tap.return",
                "session_id": app.launchEnvironment["DW_REMINDER_TEST_ID"] ?? "missing",
                "action_index": diagnosticTapIndex,
                "tap_started_monotonic_ns": began,
                "tap_returned_monotonic_ns": DispatchTime.now().uptimeNanoseconds,
                "wall_time_unix": Date().timeIntervalSince1970], attach: false)
        }
#endif
    }

    private func configureReminderDiagnostic() {
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        app.launchArguments.append("--ci-diagnostic-reminder-trace")
        diagnosticEvidence(["event": "launch.configured",
            "session_id": app.launchEnvironment["DW_REMINDER_TEST_ID"] ?? "missing",
            "observation_scope": "initial_enable",
            "monotonic_ns": DispatchTime.now().uptimeNanoseconds,
            "wall_time_unix": Date().timeIntervalSince1970], attach: true)
#endif
    }

    private func diagnosticTestEntered() {
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        if diagnosticSelected { diagnosticMarkers.record(test: name, phase: "test", edge: "enter") }
#endif
    }
    private func diagnosticWillTerminate() {
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        if diagnosticSelected {
            diagnosticMarkers.record(test: name, phase: "app_termination", edge: "enter", operationID: diagnosticTerminationID)
        }
#endif
    }
    private func diagnosticDidTerminate() {
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        if diagnosticSelected {
            diagnosticMarkers.record(test: name, phase: "app_termination", edge: "return", operationID: diagnosticTerminationID)
            diagnosticMarkers.record(test: name, phase: "test", edge: "return", terminal: true)
        }
#endif
    }

#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
    private var diagnosticSelected: Bool { name.contains("testPermissionRevocationRegrantAndExplicitDisable") }
    private let diagnosticMarkers = CIDiagnosticTestMarkers(stream: "reminder_ui")
    private let diagnosticTerminationID = UUID().uuidString
    private var diagnosticTapIndex = 0

    private func diagnosticValue(_ element: XCUIElement) -> String {
        guard let value = element.value as? String, value == "0" || value == "1" else { return "other" }
        return value
    }
    private func diagnosticError(_ element: XCUIElement) -> String {
        guard element.exists else { return "none" }
        let value = element.label
        if value.contains("history needs recovery") { return "storage_recovery" }
        if value.contains("state couldn't be verified") { return "storage_verification" }
        if value.contains("Couldn't request permission") { return "authorization_request" }
        return "other"
    }
    private func diagnosticPermission(_ element: XCUIElement) -> String {
        guard element.exists else { return "absent" }
        let value = element.label
        if value == "Notifications allowed." { return "authorized" }
        if value.hasPrefix("Quiet notifications allowed.") { return "quiet" }
        if value.hasPrefix("Blocked in iOS Settings.") { return "denied_enabled" }
        if value.hasPrefix("Notifications aren't allowed.") { return "denied_disabled" }
        if value.hasPrefix("Permission will be requested") { return "not_determined" }
        return "other"
    }
    private func diagnosticEvidence(_ evidence: [String: Any], attach: Bool) {
        guard let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        print("DW_REMINDER_UI_DIAGNOSTIC " + text)
        if attach {
            let attachment = XCTAttachment(string: text)
            attachment.name = "Reminder diagnostic state"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
#endif
}

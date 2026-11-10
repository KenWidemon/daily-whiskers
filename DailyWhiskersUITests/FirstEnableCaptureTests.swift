#if DEBUG && CI_SMOKE_TESTING && DW_SWITCH_OBSERVER
import XCTest

/// Diagnostic only. Original tests remain byte-for-byte unchanged.
final class FirstEnableCaptureTests: XCTestCase {
    private var app: XCUIApplication!
    private var request: [String: Any] = [:]
    private var directory: URL!
    private var failed = false
    private var pending = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        guard let session = env["DW_CAPTURE_SESSION"].flatMap(UUID.init(uuidString:)),
              let mode = env["DW_CAPTURE_MODE"], ["campaign", "positive", "no-input"].contains(mode) else {
            throw NSError(domain: "CaptureConfiguration", code: 1)
        }
        directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DWCapture/" + session.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        request = ["session": session.uuidString, "mode": mode]
    }
    override func record(_ issue: XCTIssue) {
        failed = true
        super.record(issue)
    }
    override func tearDownWithError() throws {
        // Assertion aborts still export the failed trial while the app is alive.
        if pending { _ = try? finish(originalPassed: false) }
        app?.terminate()
    }
    private func write(_ object: [String: Any], _ name: String) throws {
        let file = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: file.path) else {
            throw NSError(domain: "DuplicateCaptureMessage", code: 2)
        }
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: file, options: .atomic)
    }
    private func finish(originalPassed: Bool) throws -> Bool {
        pending = false
        let ordinal = request["ordinal"] as! Int
        request["originalPassed"] = originalPassed && !failed
        request["finishedMono"] = ProcessInfo.processInfo.systemUptime
        // These extra observations occur strictly AFTER the original prefix.
        if app.state == .runningForeground {
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "Capture \(ordinal) after original deadline"; image.lifetime = .keepAlways; add(image)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Capture \(ordinal) final accessibility"; tree.lifetime = .keepAlways; add(tree)
        }
        try write(request, "request-\(ordinal).json")
        let response = directory.appendingPathComponent("response-\(ordinal).json")
        let deadline = ProcessInfo.processInfo.systemUptime + 45
        while !FileManager.default.fileExists(atPath: response.path), ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: response)) as! [String: Any]
        for key in ["session", "fixture", "mode"] {
            guard value[key] as? String == request[key] as? String else { throw NSError(domain: "CaptureIdentity", code: 3) }
        }
        guard value["ordinal"] as? Int == ordinal, let decision = value["decision"] as? String,
              ["continue", "complete", "stop"].contains(decision) else { throw NSError(domain: "CaptureDecision", code: 4) }
        XCTAssertNotEqual(decision, "stop", "Host rejected trial evidence; stop without replacement")
        return decision == "continue" && !failed
    }

    // Verbatim helpers from ReminderUITests; audit enforces this.
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
    private func originalPrefix() {
        app.launch(); openSettings()
        let toggle = app.switches["reminder-enabled"]
        tapToggle(toggle); waitValue(toggle, "1"); waitEnabled(toggle)
    }
    func testCapture() throws {
        let mode = request["mode"] as! String
        let count = mode == "campaign" ? 24 : 1
        for ordinal in 1...count {
            request.removeValue(forKey: "originalPassed")
            request.removeValue(forKey: "finishedMono")
            // Original setup is repeated before launch; no new pre-tap query.
            app = XCUIApplication()
            app.launchArguments = ["--ci-smoke", "--ci-smoke-reminders", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launchEnvironment["DW_REMINDER_TEST_ID"] = UUID().uuidString
            app.launchEnvironment["DW_CAPTURE_SESSION"] = request["session"] as? String
            request["fixture"] = app.launchEnvironment["DW_REMINDER_TEST_ID"]
            request["ordinal"] = ordinal
            request["startedMono"] = ProcessInfo.processInfo.systemUptime
            try write(request, "start-\(ordinal).json")
            pending = true
            if mode == "no-input" {
                // Separate negative control, never a campaign trial.
                app.launch(); openSettings()
                Thread.sleep(forTimeInterval: 15)
                waitValue(app.switches["reminder-enabled"], "0")
            } else { originalPrefix() }
            let proceed = try finish(originalPassed: true)
            app.terminate()
            guard app.state == .notRunning else { throw NSError(domain: "CaptureTermination", code: 5) }
            if !proceed { return }
        }
    }
}
#endif

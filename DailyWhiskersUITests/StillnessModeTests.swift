import XCTest
import UIKit

final class StillnessModeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["DW_STILLNESS_TEST_ID"] = UUID().uuidString
        app.launchArguments = ["--ci-smoke", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ci-smoke-offline"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["ci-stillness-system"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["ci-stillness-system"].label, "System Reduce Motion: Off",
                       "Motion-positive controls require a dedicated simulator with system Reduce Motion off.")
    }

    override func tearDownWithError() throws {
        capture("Final state, including unexpected behavior")
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
    }

    func testPersistenceLifecycleCardNavigationAndAuth() {
        openSettings()
        // Observe the native default before any write in this UUID-owned domain.
        XCTAssertEqual(app.switches["stillness-toggle"].value as? String, "0")
        app.buttons["Done"].tap()
        assertAnimatedBackground("Today app off / system off — positive control")
        openSettings()
        setStillness(true)
        capture("Stillness on — native setting and system explanation")
        app.buttons["Done"].tap()
        let quote = element("daily-card-quote")
        XCTAssertTrue(quote.waitForExistence(timeout: 10))
        let original = quote.label
        let bounds = quote.frame
        assertStaticBackground("Today still")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(quote.label, original)
        XCTAssertEqual(quote.frame, bounds)
        assertStaticBackground("Today after foreground")
        app.terminate()
        app.launch()
        openSettings()
        XCTAssertEqual(app.switches["stillness-toggle"].value as? String, "1")
        app.buttons["Done"].tap()
        XCTAssertEqual(quote.label, original)

        app.buttons["card-menu"].tap()
        app.buttons["Open Bonus Card"].tap()
        XCTAssertTrue(element("bonus-card-quote").waitForExistence(timeout: 15))
        assertStaticBackground("Bonus still")
        let options = app.buttons["daily-card-options"]
        if options.value as? String != "Saved" { app.toggleDailyCardSave() }
        let bonusQuote = element("bonus-card-quote").label
        app.buttons["open-saved-cards"].tap()
        let saved = app.buttons.matching(identifier: "saved-card-row")
            .matching(NSPredicate(format: "label == %@", bonusQuote)).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.tap()
        XCTAssertTrue(element("saved-card-quote").waitForExistence(timeout: 10))
        assertStaticBackground("Saved detail still")

        // Prove the auth sampling region detects motion too, before requiring stillness.
        app.terminate()
        app.launch()
        openSettings()
        setStillness(false)
        app.buttons["Done"].tap()
        app.buttons["Settings"].tap()
        app.buttons["Sign In"].tap()
        XCTAssertTrue(app.scrollViews["auth-form"].waitForExistence(timeout: 10))
        assertAnimatedBackground("Sign In positive motion control")
        app.buttons["Close"].tap()
        openSettings()
        setStillness(true)
        app.buttons["Done"].tap()
        app.buttons["Settings"].tap()
        app.buttons["Sign In"].tap()
        XCTAssertTrue(app.scrollViews["auth-form"].waitForExistence(timeout: 10))
        assertStaticBackground("Sign In still")
        let create = app.buttons["Create Account"]
        for _ in 0..<5 where !create.isHittable { app.scrollViews["auth-form"].swipeUp() }
        XCTAssertTrue(create.isHittable)
        create.tap()
        XCTAssertTrue(app.textFields["registration-email"].waitForExistence(timeout: 5))
        assertStaticBackground("Create Account still")
        app.buttons["Close"].tap()
        openSettings()
        XCTAssertEqual(app.switches["stillness-toggle"].value as? String, "1")
        setStillness(false)
        app.buttons["Done"].tap()
        app.terminate()
        app.launch()
        openSettings()
        XCTAssertEqual(app.switches["stillness-toggle"].value as? String, "0")
        capture("Stillness off survives relaunch")
        app.buttons["Done"].tap()
        assertAnimatedBackground("App-off motion resumes after relaunch")
    }

    func testAppPreferenceLiveChangesAndMotionResumption() {
        openSettings()
        XCTAssertEqual(app.switches["stillness-toggle"].value as? String, "0")
        app.buttons["Done"].tap()
        let quote = element("daily-card-quote")
        XCTAssertTrue(quote.waitForExistence(timeout: 10))
        let original = quote.label
        let bounds = quote.frame
        assertAnimatedBackground("App off / actual system off positive control")

        for _ in 0..<2 {
            openSettings()
            setStillness(true)
            app.buttons["Done"].tap()
            assertStaticBackground("App on takes effect on the mounted card")
            openSettings()
            setStillness(false)
            app.buttons["Done"].tap()
            assertAnimatedBackground("App off resumes on the mounted card")
        }
        XCTAssertEqual(quote.label, original)
        XCTAssertEqual(quote.frame, bounds)
        // All four actual OS combinations and live OS changes are mandatory manual cases.
        // accessibilityReduceMotion is read-only; this test does not fake its propagation.
    }

    func testLargestTextSettingInPortraitAndLandscape() {
        app.terminate()
        app.launchArguments = ["--ci-smoke", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ci-smoke-offline"].waitForExistence(timeout: 15))
        openSettings()
        setStillness(true)
        XCTAssertTrue(app.buttons["Done"].isHittable)
        capture("Largest text Stillness portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.switches["stillness-toggle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["stillness-toggle"].isHittable)
        XCTAssertTrue(app.buttons["Done"].isHittable)
        capture("Largest text Stillness landscape")
        app.buttons["Done"].tap()
        XCTAssertTrue(element("daily-card-content").waitForExistence(timeout: 5))
        capture("Largest text static card")
    }

    private func openSettings() {
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        app.buttons["open-stillness"].tap()
        XCTAssertTrue(app.switches["stillness-toggle"].waitForExistence(timeout: 5))
    }

    private func setStillness(_ enabled: Bool) {
        let toggle = app.switches["stillness-toggle"]
        let expected = enabled ? "1" : "0"
        if toggle.value as? String != expected { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, expected)
    }

    private func assertStaticBackground(_ name: String) {
        let samples = motionSamples()
        guard samples.count == 3 else { return }
        XCTAssertEqual(samples[0], samples[1], "Rendered content changed with stillness effective")
        XCTAssertEqual(samples[1], samples[2], "Rendered content changed with stillness effective")
        capture(name)
    }

    private func assertAnimatedBackground(_ name: String) {
        let samples = motionSamples()
        guard samples.count == 3 else { return }
        XCTAssertTrue(samples[0] != samples[1] || samples[1] != samples[2],
                      "Positive control failed: this region did not detect decorative motion")
        capture(name)
    }

    private func motionSamples() -> [Data] {
        // Let menus/sheets settle before sampling. No retries or discarded failed samples.
        separateFrames()
        var samples: [Data] = []
        for index in 0..<3 {
            if index > 0 { separateFrames() }
            guard let pixels = contentPixels() else {
                XCTFail("Motion sample must contain actual pixels")
                return []
            }
            samples.append(pixels)
        }
        return samples
    }

    private func separateFrames() {
        let pause = expectation(description: "Separated motion frames")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { pause.fulfill() }
        wait(for: [pause], timeout: 3)
    }

    private func contentPixels() -> Data? {
        let window = app.windows.firstMatch
        let screenshot = window.screenshot().image
        guard let image = screenshot.cgImage else { return nil }
        let scale = CGFloat(image.width) / screenshot.size.width
        let ids = ["auth-form", "saved-card-content", "bonus-card-content", "daily-card-content"]
        guard let content = ids.map({ app.scrollViews[$0] }).first(where: { $0.exists && $0.isHittable }) else { return nil }
        // Sample the full rendered content viewport, including broad exposed background
        // on iPad and the upper/marginal background on iPhone. Exclude toolbar, clock and
        // fixture control. Positive controls must demonstrate sensitivity on each device.
        let bounds = content.frame.intersection(window.frame).insetBy(dx: 2, dy: 2)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let rect = CGRect(x: (bounds.minX - window.frame.minX) * scale,
                          y: (bounds.minY - window.frame.minY) * scale,
                          width: bounds.width * scale, height: bounds.height * scale)
        guard let cropped = image.cropping(to: rect) else { return nil }
        // This detects visible changes only. It cannot establish timeline shutdown or power use.
        return UIImage(cgImage: cropped).pngData()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}

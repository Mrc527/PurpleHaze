import XCTest

/// Exercises real screens and Keychain-backed profile persistence without starting a VPN.
/// Run on a dedicated simulator: synthetic profiles are deleted on successful completion.
@MainActor
final class ProfileUITests: XCTestCase {
    private let app = XCUIApplication()
    private let dummyKey = Data(repeating: 0xA5, count: 32).base64EncodedString()

    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "System password save prompt") { alert in
            if alert.buttons["Not Now"].exists { alert.buttons["Not Now"].tap(); return true }
            return false
        }
        launch()
        XCTAssertTrue(app.buttons["profile.new"].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        if let run = testRun, run.totalFailureCount > 0 { screenshot("Failure state") }
        app.terminate()
    }

    func testProfilesKeepIndependentCredentialsAndSettingsAcrossRelaunch() throws {
        let suffix = UUID().uuidString.prefix(6)
        let secure = "Studio Secure \(suffix)"
        let legacy = "Travel Legacy \(suffix)"

        tap(app.buttons["profile.new"])
        setText("name", secure)
        setText("domain", "secure.example.com")
        save()
        XCTAssertTrue(app.alerts["Unable to continue"].waitForExistence(timeout: 3), "An encrypted profile must reject a missing key")
        app.alerts.buttons["OK"].tap()
        setText("key", dummyKey)
        tap(app.switches["profile.proxy"])
        screenshot("01 Encrypted profile editor")
        save()
        XCTAssertTrue(app.buttons["profile.edit.\(secure)"].waitForExistence(timeout: 5))

        tap(app.buttons["profile.new"])
        setText("name", legacy)
        setText("domain", "legacy.example.com")
        tap(app.segmentedControls["profile.security"].buttons["Legacy"])
        XCTAssertFalse(app.switches["profile.proxy"].isEnabled)
        setText("password", "synthetic-password")
        setText("dns", "9.9.9.9")
        save()
        XCTAssertTrue(app.buttons["profile.edit.\(legacy)"].waitForExistence(timeout: 5))
        tap(app.buttons["profile.select.\(legacy)"])
        XCTAssertEqual(app.buttons["profile.select.\(legacy)"].label, "Selected")
        screenshot("02 Two independent profiles")

        app.terminate()
        launch()
        XCTAssertTrue(app.buttons["profile.select.\(legacy)"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["profile.select.\(legacy)"].label, "Selected", "Selection must survive relaunch")
        tap(app.buttons["profile.edit.\(legacy)"])
        XCTAssertTrue(app.segmentedControls["profile.security"].buttons["Legacy"].isSelected)
        XCTAssertFalse((field("password").value as? String ?? "").isEmpty, "Legacy credential must survive relaunch")
        XCTAssertEqual(field("dns").value as? String, "9.9.9.9")
        cancel()

        tap(app.buttons["profile.edit.\(secure)"])
        XCTAssertTrue(app.segmentedControls["profile.security"].buttons["Encrypted"].isSelected)
        XCTAssertEqual(app.switches["profile.proxy"].value as? String, "1")
        XCTAssertFalse((field("key").value as? String ?? "").isEmpty, "Encrypted profile must retain its own key")
        XCTAssertEqual(field("dns").value as? String, "1.1.1.1", "Editing another profile must not overwrite DNS")
        screenshot("03 Restored encrypted profile")
        setText("name", "Unsaved change")
        cancel()
        XCTAssertTrue(app.buttons["profile.edit.\(secure)"].exists)
        XCTAssertFalse(app.buttons["profile.edit.Unsaved change"].exists)

        tap(app.buttons["profile.edit.\(legacy)"])
        tap(app.buttons["Delete profile"])
        app.alerts.buttons["Cancel"].tap()
        cancel()
        XCTAssertTrue(app.buttons["profile.edit.\(legacy)"].exists)
        delete(legacy)
        XCTAssertTrue(app.buttons["profile.edit.\(secure)"].exists)
        XCTAssertEqual(app.buttons["profile.select.\(secure)"].label, "Selected", "Deleting selection must select remaining profile")
        screenshot("04 Profile after deleting selection")
        delete(secure)
        XCTAssertFalse(app.buttons["profile.edit.\(secure)"].exists)
        XCTAssertFalse(app.buttons["profile.edit.\(legacy)"].exists)
    }

    private func launch() {
        app.launch()
        // The iOS simulator has no NetworkExtension preferences daemon. Keep
        // profile/Keychain UI tests real while acknowledging this platform limit.
        if app.alerts.firstMatch.waitForExistence(timeout: 3),
           app.alerts.staticTexts["IPC failed"].exists {
            app.alerts.buttons["OK"].tap()
        }
    }
    private func field(_ key: String) -> XCUIElement {
        let ordinary = app.textFields["profile.\(key)"]
        return ordinary.exists ? ordinary : app.secureTextFields["profile.\(key)"]
    }
    private var scroll: XCUIElement {
        let editor = app.scrollViews["profile.editor.scroll"]
        return editor.exists ? editor : app.scrollViews.firstMatch
    }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        dismissKeyboardIntroduction()
        for _ in 0..<24 {
            if element.isHittable { break }
            let surface = scroll
            let upward = element.frame.midY >= surface.frame.midY || element.frame == .zero
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.75 : 0.35))
            let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.35 : 0.75))
            start.press(forDuration: 0.1, thenDragTo: end)
            dismissKeyboardIntroduction()
        }
        XCTAssertTrue(element.isHittable, "Cannot reach \(element.identifier)", file: file, line: line)
        element.tap()
    }
    private func setText(_ key: String, _ value: String) {
        let element = field(key)
        tap(element)
        dismissKeyboardIntroduction()
        let existing = element.value as? String ?? ""
        // Every field edited here is either empty or an ordinary text field.
        if !existing.isEmpty {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        element.typeText(value)
    }
    private func dismissKeyboardIntroduction() {
        if app.staticTexts["Save Password?"].exists, app.buttons["Not Now"].exists {
            app.buttons["Not Now"].tap()
        }
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Speed up your typing")).firstMatch
        if message.exists, app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
    }
    private func save() { app.navigationBars.buttons["Save"].firstMatch.tap() }
    private func cancel() {
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Discard"].tap()
    }
    private func delete(_ name: String) {
        tap(app.buttons["profile.edit.\(name)"])
        tap(app.buttons["Delete profile"])
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["profile.new"].waitForExistence(timeout: 5))
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

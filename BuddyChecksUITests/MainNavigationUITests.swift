import XCTest

@MainActor final class MainNavigationUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(connected: Bool, persistent: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BUDDY_CHECKS_TEST_STORE"] = UUID().uuidString
        if connected { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_FIXTURE"] = "1" }
        if persistent {
            // Use the UUID-isolated encrypted workflow journal for unsigned simulator builds.
            app.launchEnvironment["BUDDY_CHECKS_CONNECTED_WORKFLOW_STORE"] = "1"
        }
        app.launch()
        return app
    }
    private func tap(_ label: String, app: XCUIApplication) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing \(label)")
        for _ in 0..<8 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable); button.tap()
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testConnectedHomeAndFollowUpsAreMainTabsAndSettingsContainsOnlyAccountDetails() {
        let app = launch(connected: true)
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Choose a member"].isHittable)
        XCTAssertTrue(app.tabBars.buttons["Home"].exists && app.tabBars.buttons["Follow-ups"].exists)
        capture("Connected main Home", app: app)
        app.tabBars.buttons["Follow-ups"].tap()
        XCTAssertTrue(app.staticTexts["You have no recorded follow-ups."].waitForExistence(timeout: 10))
        capture("Connected Follow-ups tab", app: app)
        app.tabBars.buttons["Home"].tap()
        tap("Account and Post settings", app: app)
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Jamie Example"].exists)
        XCTAssertFalse(app.buttons["Choose a member"].isHittable)
        XCTAssertFalse(app.buttons["Continue with Alex"].isHittable)
        capture("Account settings without workflow actions", app: app)
        tap("Done", app: app)
        XCTAssertTrue(app.buttons["Choose a member"].waitForExistence(timeout: 10))
        tap("Account and Post settings", app: app); tap("Sign out", app: app)
        tap("Sign out and remove unfinished work", app: app)
        XCTAssertTrue(app.staticTexts["Signed out."].waitForExistence(timeout: 10))
        tap("Done", app: app)
        XCTAssertTrue(app.buttons["Sign in"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Your checks"].exists)
        capture("Signed out recovery on main screen", app: app)
    }
    func testProtectedDraftRestoresDirectlyOnHomeWithoutOpeningSettings() {
        let app = launch(connected: true, persistent: true)
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 15))
        tap("Choose a member", app: app)
        let search = app.textFields["Search by name"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Alex\n")
        tap("Alex Example", app: app); tap("Record a check", app: app)
        XCTAssertTrue(app.staticTexts["Alex Example"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Continue with Alex"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
        capture("Unfinished check directly on reopened Home", app: app)
        tap("Continue with Alex", app: app)
        XCTAssertTrue(app.staticTexts["Alex Example"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Save to Post"].isEnabled)
        tap("Check options", app: app); tap("Discard unfinished check", app: app); tap("Discard check", app: app)
        XCTAssertTrue(app.buttons["Choose a member"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Continue with Alex"].exists)
        tap("Account and Post settings", app: app); tap("Sign out", app: app)
        tap("Sign out and remove unfinished work", app: app)
        XCTAssertTrue(app.staticTexts["Signed out."].waitForExistence(timeout: 10))
    }
    func testUnconfiguredLocalHomeKeepsWorkflowAndSettingsSeparate() {
        let app = launch(connected: false)
        XCTAssertTrue(app.buttons["Choose a member"].waitForExistence(timeout: 15))
        tap("Account and Post settings", app: app)
        XCTAssertTrue(app.textFields["Post website"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Public app ID"].exists)
        XCTAssertFalse(app.buttons["Choose a member"].isHittable)
        capture("Unconfigured account settings", app: app)
        tap("Done", app: app)
        XCTAssertTrue(app.buttons["Choose a member"].isHittable)
        XCTAssertTrue(app.tabBars.buttons["Follow-ups"].exists)
    }
}

import XCTest

/// Run permission cases on separate disposable simulators. These use actual OS notifications.
@MainActor final class ReminderUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(seconds: Int = 300, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BUDDY_CHECKS_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["BUDDY_CHECKS_TEST_REMINDER_SECONDS"] = String(seconds)
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Robert Miller, Follow up")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        row.tap()
        return app
    }
    private func tap(_ label: String, app: XCUIApplication) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        for _ in 0..<8 where !button.isHittable { app.swipeUp() }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        XCTAssertTrue(button.isHittable); button.tap()
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + " tree"; tree.lifetime = .keepAlways; add(tree)
    }
    private func respondToPermission(allow: Bool) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8), "Use a fresh reminder-test simulator for permission evidence")
        let button = alert.buttons[allow ? "Allow" : "Don’t Allow"]
        if button.exists { button.tap() }
        else { alert.buttons[allow ? "Allow" : "Don't Allow"].tap() }
    }
    func testNativeDenialRetainsFollowUpAtLargestText() {
        let app = launch(largeText: true)
        tap("Remind me on this iPhone", app: app)
        respondToPermission(allow: false)
        XCTAssertTrue(app.staticTexts["Notifications are off. Your follow-up is saved in the app."].waitForExistence(timeout: 8))
        capture("Reminder denied largest text", app: app)
        tap("Dismiss reminder", app: app)
        XCTAssertTrue(app.staticTexts["No phone alert is scheduled."].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Robert Miller, Follow up")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        XCTAssertTrue(app.staticTexts["No phone alert is scheduled."].exists)
        tap("Mark complete", app: app)
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))
    }
    func testNativeReminderDeliveryReturnsToCurrentFollowUp() {
        let app = launch(seconds: 75)
        tap("Remind me on this iPhone", app: app)
        respondToPermission(allow: true)
        XCTAssertTrue(app.staticTexts["Reminder scheduled on this iPhone."].waitForExistence(timeout: 8))
        capture("Reminder scheduled ordinary", app: app)
        app.terminate(); app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Robert Miller, Follow up")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.staticTexts["Reminder scheduled on this iPhone."].waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notification = springboard.staticTexts["Buddy Check follow-up"]
        XCTAssertTrue(notification.waitForExistence(timeout: 85), "Actual local notification did not appear")
        capture("Reminder delivered by iOS", app: springboard)
        XCTAssertFalse(springboard.staticTexts["Robert Miller"].exists)
        notification.tap()
        XCTAssertTrue(app.navigationBars["Your follow-up"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Robert Miller"].exists)
        XCTAssertTrue(app.staticTexts["The reminder time has passed. Your follow-up is still open."].waitForExistence(timeout: 8))
        capture("Reminder returned to current follow-up", app: app)
        tap("Mark complete", app: app)
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))
        capture("Reminder completed", app: app)
        tap("View original check", app: app)
        XCTAssertTrue(app.staticTexts["No answer"].exists)
    }
    func testNativeReminderCancellationAfterRelaunch() {
        let app = launch()
        tap("Remind me on this iPhone", app: app)
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 2) { alert.buttons["Allow"].tap() }
        XCTAssertTrue(app.staticTexts["Reminder scheduled on this iPhone."].waitForExistence(timeout: 8))
        app.terminate(); app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Robert Miller, Follow up")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.staticTexts["Reminder scheduled on this iPhone."].waitForExistence(timeout: 8))
        tap("Dismiss reminder", app: app)
        // This status is published only after the actual OS queue confirms removal.
        XCTAssertTrue(app.staticTexts["No phone alert is scheduled."].waitForExistence(timeout: 8))
        capture("Reminder cancelled after relaunch", app: app)
        tap("Cancel follow-up", app: app)
        let confirmation = app.sheets.buttons["Cancel follow-up"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); confirmation.tap()
        XCTAssertTrue(app.staticTexts["Cancelled"].waitForExistence(timeout: 5))
    }
    func testNotificationColdLaunchUsesNormalStorage() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_COLD_REMINDER"] == "1",
                          "Requires an explicitly prepared disposable simulator")
        let correctDevice = environment["SIMULATOR_DEVICE_NAME"] == "Buddy Checks Cold Reminder"
        XCTAssertTrue(correctDevice, "Never run a normal-storage fixture test on another simulator")
        guard correctDevice else { return }

        // Fixture preparation is external. No app launch environment selects or seeds a store.
        let app = XCUIApplication()
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Robert Miller, Follow up")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        row.tap()
        tap("Remind me on this iPhone", app: app)
        respondToPermission(allow: true)
        XCTAssertTrue(app.staticTexts["Reminder scheduled on this iPhone."].waitForExistence(timeout: 8))
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notification = springboard.staticTexts["Buddy Check follow-up"]
        var delivered = false
        for _ in 0..<6 {
            if notification.waitForExistence(timeout: 55) { delivered = true; break }
        }
        XCTAssertTrue(delivered, "Actual local notification did not appear")
        guard delivered else { return }
        XCTAssertEqual(app.state, .notRunning, "Notification must open a terminated app")
        capture("Cold reminder delivered while app terminated", app: springboard)
        XCTAssertFalse(springboard.staticTexts["Robert Miller"].exists)
        notification.tap() // No app.launch(): SpringBoard must cold-start and route the app.
        XCTAssertTrue(app.navigationBars["Your follow-up"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Robert Miller"].exists)
        XCTAssertTrue(app.staticTexts["The reminder time has passed. Your follow-up is still open."].waitForExistence(timeout: 8))
        capture("Cold reminder opened current follow-up", app: app)
        tap("Mark complete", app: app)
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))
        tap("View original check", app: app)
        XCTAssertTrue(app.staticTexts["No answer"].exists)
    }
    func testReminderVoiceOverAtLargestText() throws {
        let app = launch(largeText: true)
        if #available(iOS 27.0, *) {
            let service = XCUIDevice.shared.voiceOverService
            let wasEnabled = service.isEnabled
            defer { if !wasEnabled { try? service.disable() } }
            try service.enable()
            var speech = [try service.currentSpeech().utterance]
            for _ in 0..<35 {
                let next = try service.moveForward().utterance
                if next == speech.last { break }
                speech.append(next)
            }
            let transcript = speech.joined(separator: "\n")
            let attachment = XCTAttachment(string: transcript); attachment.name = "Reminder VoiceOver largest text"; attachment.lifetime = .keepAlways; add(attachment)
            for phrase in ["phone reminder", "no phone alert is scheduled", "remind me on this iphone", "mark complete"] {
                XCTAssertTrue(transcript.lowercased().contains(phrase), "Missing spoken control: \(phrase)")
            }
        }
    }

    func testActionableNotificationSnoozeAndDismiss() throws { try exerciseSnooze(largest: false, delivery: true) }
    func testSnoozeChoicesAtLargestTextWithVoiceOver() throws { try exerciseSnooze(largest: true, delivery: false) }

    private func exerciseSnooze(largest: Bool, delivery: Bool) throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_REMINDER_SNOOZE"] == "1", "Run only on an owned reminder simulator.")
        XCTAssertTrue(["Buddy Checks Reminder Snooze", "Buddy Checks Connected Reminder Snooze"].contains(environment["SIMULATOR_DEVICE_NAME"] ?? ""))
        if #available(iOS 27.0, *) { try XCUIDevice.shared.voiceOverService.disable() }
        let app = launch(seconds: delivery ? 75 : 600, largeText: largest)
        let store = try XCTUnwrap(app.launchEnvironment["BUDDY_CHECKS_TEST_STORE"])
        let identity = XCTAttachment(string: store); identity.name = "Local snooze store"; identity.lifetime = .keepAlways; add(identity)
        tap("Remind me on this iPhone", app: app)
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 3) { alert.buttons["Allow"].tap() }
        XCTAssertTrue(app.staticTexts["Reminder scheduled on this iPhone."].waitForExistence(timeout: 10))
        if delivery {
            XCUIDevice.shared.press(.home)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let body = springboard.staticTexts["Call Robert for a Buddy Check"]
            XCTAssertTrue(body.waitForExistence(timeout: 85))
            capture("Actionable Robert notification", app: springboard)
            body.tap()
            XCTAssertTrue(app.navigationBars["Your follow-up"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["The reminder time has passed. Your follow-up is still open."].waitForExistence(timeout: 10))
        }
        tap("Snooze reminder", app: app)
        XCTAssertTrue(app.navigationBars["Snooze reminder"].waitForExistence(timeout: 5))
        for label in ["15 minutes", "1 hour", "Tomorrow at 9 AM", "snooze-sheet-dismiss"] { XCTAssertTrue(app.buttons[label].exists) }
        capture("Snooze choices \(largest ? "largest" : "ordinary")", app: app)
        if largest, #available(iOS 27.0, *) {
            let service = XCUIDevice.shared.voiceOverService
            addTeardownBlock { @MainActor in try? service.disable() }
            try service.enable()
            var speech = [try service.currentSpeech().utterance]
            for _ in 0..<22 {
                let next = try service.moveForward().utterance
                if next == speech.last { break }; speech.append(next)
            }
            try service.disable()
            let transcript = speech.joined(separator: "\n")
            let attachment = XCTAttachment(string: transcript); attachment.name = "Snooze choices VoiceOver"; attachment.lifetime = .keepAlways; add(attachment)
            for label in ["15 minutes", "1 hour", "Tomorrow at 9", "Dismiss reminder", "Cancel"] { XCTAssertTrue(transcript.localizedCaseInsensitiveContains(label)) }
        }
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["reminder-snoozed-until"].exists)
        tap("Snooze reminder", app: app); tap("15 minutes", app: app)
        XCTAssertTrue(app.staticTexts["reminder-snoozed-until"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Reminder scheduled on this iPhone."].exists)
        capture("Snoozed reminder \(largest ? "largest" : "ordinary")", app: app)
        app.terminate(); app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Robert Miller, Follow up")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }; row.tap()
        XCTAssertTrue(app.staticTexts["reminder-snoozed-until"].waitForExistence(timeout: 10))
        tap("Snooze reminder", app: app); tap("1 hour", app: app)
        XCTAssertTrue(app.staticTexts["Reminder scheduled on this iPhone."].waitForExistence(timeout: 10))
        tap("Snooze reminder", app: app)
        for _ in 0..<8 where !app.buttons["snooze-sheet-dismiss"].isHittable { app.swipeUp() }
        capture("Dismiss choice in snooze sheet \(largest ? "largest" : "ordinary")", app: app)
        tap("snooze-sheet-dismiss", app: app)
        XCTAssertTrue(app.staticTexts["No phone alert is scheduled."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["reminder-snoozed-until"].exists)
        capture("Dismissed reminder keeps follow-up \(largest ? "largest" : "ordinary")", app: app)
        XCTAssertTrue(app.buttons["Mark complete"].exists)
        tap("View original check", app: app)
        XCTAssertTrue(app.staticTexts["No answer"].waitForExistence(timeout: 10))
    }
}

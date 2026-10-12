import XCTest

/// Each permission case requires its own named disposable simulator. The guarded
/// fixture fakes the Post, while Keychain, encrypted journal and iOS alerts are real.
@MainActor final class ConnectedReminderUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(seconds: Int, largest: Bool = false) -> XCUIApplication {
        XCTAssertTrue(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("Buddy Checks Connected Reminder") == true)
        let app = XCUIApplication()
        app.launchEnvironment["BUDDY_CHECKS_CONNECTED_REMINDER_SECONDS"] = String(seconds)
        if largest { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10))
        openFollowUp(app)
        return app
    }
    private func openFollowUp(_ app: XCUIApplication) {
        tap("Your follow-ups", app: app)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex Example,")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); reveal(row, app: app); row.tap()
        XCTAssertTrue(app.staticTexts["Alex Example"].waitForExistence(timeout: 10))
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<24 {
            let sheet = app.navigationBars["Snooze reminder"]
            let top = (sheet.exists ? sheet : app.navigationBars.firstMatch).frame.maxY + 8
            let bottom = app.frame.maxY - 35
            if element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom { return }
            let upwards = element.frame.minY >= top
            if sheet.exists {
                // A short held drag beginning on a duration can activate that
                // button in the native sheet. Use its scroll view's swipe.
                guard let scroll = app.scrollViews.allElementsBoundByIndex.last else {
                    XCTFail("Snooze sheet has no scroll view"); return
                }
                if upwards { scroll.swipeUp() } else { scroll.swipeDown() }
                continue
            }
            // Keep the gesture inside content, away from the scrollbar's wider
            // hit region on a small screen; dragging that thumb reverses the
            // content movement used by this positioning calculation.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.76 : 0.36))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.44 : 0.68))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
        }
        XCTFail("Could not reveal \(element.label)")
    }
    private func tap(_ name: String, app: XCUIApplication) {
        let navigationButton = app.navigationBars.buttons[name]
        if navigationButton.exists && navigationButton.isHittable { navigationButton.tap(); return }
        let button = app.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 10)); reveal(button, app: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 30), .completed, "Action stayed disabled: \(name)")
        button.tap()
    }
    private func permission(_ allowed: Bool) {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Use a fresh device for permission evidence")
        if allowed { alert.buttons["Allow"].tap() }
        else if alert.buttons["Don’t Allow"].exists { alert.buttons["Don’t Allow"].tap() }
        else { alert.buttons["Don't Allow"].tap() }
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + " tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func testColdNotificationOpensCurrentConnectedRecordThenReschedulesAndSignsOut() {
        let app = launch(seconds: 110)
        tap("Remind me on this iPhone", app: app); permission(true)
        XCTAssertTrue(app.staticTexts["Reminder scheduled on this iPhone."].waitForExistence(timeout: 10))
        capture("Connected reminder scheduled ordinary", app: app)
        app.terminate(); XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notification = springboard.staticTexts["Buddy Check follow-up"]
        var delivered = false
        for _ in 0..<4 { if notification.waitForExistence(timeout: 40) { delivered = true; break } }
        XCTAssertTrue(delivered)
        XCTAssertEqual(app.state, .notRunning)
        XCTAssertTrue(springboard.staticTexts["Check in with Alex for a Buddy Check"].exists)
        capture("Connected named notification while terminated", app: springboard)
        XCTAssertFalse(springboard.staticTexts["Alex Example"].exists)
        notification.tap() // No app.launch: SpringBoard must restore the account and link.
        XCTAssertTrue(app.navigationBars["Follow-up"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Alex Example"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["The reminder time has passed. Your follow-up is still open."].waitForExistence(timeout: 10))
        capture("Connected cold reminder resolved current record", app: app)
        tap("Reschedule", app: app)
        tap("Save new follow-up time", app: app)
        XCTAssertTrue(app.staticTexts["Reminder scheduled on this iPhone."].waitForExistence(timeout: 10))
        reveal(app.staticTexts["Reminder scheduled on this iPhone."], app: app)
        capture("Connected reminder rescheduled", app: app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 15)); openFollowUp(app)
        XCTAssertTrue(app.staticTexts["Reminder scheduled on this iPhone."].waitForExistence(timeout: 10))
        for _ in 0..<2 { app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap() }
        tap("Account and Post settings", app: app); tap("Sign out", app: app)
        let signOut = app.buttons["Sign out and remove unfinished work"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 10)); signOut.tap()
        XCTAssertTrue(app.staticTexts["Signed out."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["A phone alert may remain. Reopen the app to retry removing it."].exists)
        capture("Connected sign-out after verified alert removal", app: app)
    }
    func testDeniedReminderRetainsFollowUpAtLargestTextWithVoiceOver() throws {
        let app = launch(seconds: 3600, largest: true)
        tap("Remind me on this iPhone", app: app); permission(false)
        let denied = app.staticTexts["Notifications are off. Your follow-up is saved with the Post."]
        XCTAssertTrue(denied.waitForExistence(timeout: 10)); reveal(denied, app: app)
        capture("Connected denied reminder largest text", app: app)
        if #available(iOS 27.0, *) {
            reveal(app.staticTexts["Alex Example"], app: app)
            let voiceOver = XCUIDevice.shared.voiceOverService
            let wasEnabled = voiceOver.isEnabled
            try voiceOver.enable()
            defer { if !wasEnabled { try? voiceOver.disable() } }
            var speech = [try voiceOver.currentSpeech().utterance]
            for _ in 0..<38 {
                let next = try voiceOver.moveForward().utterance
                if next == speech.last { break }; speech.append(next)
            }
            let transcript = speech.joined(separator: "\n")
            let attachment = XCTAttachment(string: transcript); attachment.name = "Connected reminder VoiceOver largest text"; attachment.lifetime = .keepAlways; add(attachment)
            for phrase in ["Phone reminder", "Notifications are off", "Open notification settings", "Dismiss reminder"] {
                XCTAssertTrue(transcript.localizedCaseInsensitiveContains(phrase), "Missing spoken control: \(phrase)")
            }
        }
        tap("Dismiss reminder", app: app)
        XCTAssertTrue(app.staticTexts["No phone alert is scheduled."].waitForExistence(timeout: 10))
        reveal(app.staticTexts["No phone alert is scheduled."], app: app)
        capture("Connected reminder off largest text", app: app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 15)); openFollowUp(app)
        XCTAssertTrue(app.staticTexts["No phone alert is scheduled."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Open"].exists)
    }

    func testConnectedSnoozeRestoresAndDismissesAtLargestText() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BUDDY_CHECKS_REMINDER_SNOOZE"] == "1", "Uses an owned synthetic reminder simulator.")
        if #available(iOS 27.0, *) { try XCUIDevice.shared.voiceOverService.disable() }
        let app = launch(seconds: 600, largest: true)
        let status = app.staticTexts["connected-reminder-status"]
        let checked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "Checking phone reminder…"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [checked], timeout: 15), .completed)
        // A retained test fixture may recover a previously rejected OS add on
        // launch. Preserve that intent and use the app's explicit retry route.
        if status.label != "Reminder scheduled on this iPhone." {
            tap(app.buttons["Retry phone reminder"].exists ? "Retry phone reminder" : "Remind me on this iPhone", app: app)
            let prompt = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
            if prompt.waitForExistence(timeout: 3) { prompt.buttons["Allow"].tap() }
        }
        XCTAssertTrue(app.staticTexts["Reminder scheduled on this iPhone."].waitForExistence(timeout: 10))
        tap("Snooze reminder", app: app)
        XCTAssertTrue(app.buttons["Tomorrow at 9 AM"].waitForExistence(timeout: 5))
        reveal(app.buttons["15 minutes"], app: app)
        capture("Connected snooze choices largest", app: app)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["reminder-snoozed-until"].exists)
        tap("Snooze reminder", app: app); tap("15 minutes", app: app)
        let snoozed = app.staticTexts["reminder-snoozed-until"]
        XCTAssertTrue(snoozed.waitForExistence(timeout: 10)); reveal(snoozed, app: app)
        let firstTime = snoozed.label
        capture("Connected snoozed largest", app: app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 15)); openFollowUp(app)
        XCTAssertTrue(snoozed.waitForExistence(timeout: 10)); XCTAssertEqual(snoozed.label, firstTime)
        tap("Snooze reminder", app: app); tap("1 hour", app: app)
        XCTAssertTrue(snoozed.waitForExistence(timeout: 10)); XCTAssertNotEqual(snoozed.label, firstTime)
        tap("Snooze reminder", app: app)
        reveal(app.buttons["snooze-sheet-dismiss"], app: app)
        capture("Connected dismiss choice in snooze sheet largest", app: app)
        tap("snooze-sheet-dismiss", app: app)
        let dismissed = app.staticTexts["No phone alert is scheduled."]
        XCTAssertTrue(dismissed.waitForExistence(timeout: 10)); reveal(dismissed, app: app)
        capture("Connected dismissal leaves follow-up open", app: app)
        XCTAssertFalse(snoozed.exists); XCTAssertTrue(app.staticTexts["Open"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 15)); openFollowUp(app)
        XCTAssertTrue(dismissed.waitForExistence(timeout: 10)); XCTAssertTrue(app.staticTexts["Open"].exists)
    }
}

import XCTest

/// Ordinary-size workflow checks. Uses only the isolated synthetic Post service.
@MainActor final class StandardWorkflowUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(persist: Bool = false, lostResponse: Bool = false, staleCorrection: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BUDDY_CHECKS_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["BUDDY_CHECKS_CONNECTED_FIXTURE"] = "1"
        if persist { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_WORKFLOW_STORE"] = "1" }
        if lostResponse { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_LOST_RESPONSE"] = "1" }
        if staleCorrection { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_STALE_CORRECTION"] = "1" }
        app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 15))
        return app
    }
    private func tap(_ label: String, _ app: XCUIApplication) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing \(label)")
        button.tap()
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func begin(_ app: XCUIApplication) {
        tap("Check on someone, Search the Post member list", app)
        let search = app.textFields["Search by name"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Alex\n")
        tap("Alex Example", app)
        XCTAssertTrue(app.buttons["Record a check"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Record a check"].isHittable)
        XCTAssertFalse(app.staticTexts["“Hi Alex, I'm checking in from the Post. How have you been?”"].isHittable)
        capture("Standard member actions", app)
        tap("Record a check", app)
        XCTAssertTrue(app.buttons["Save to Post"].waitForExistence(timeout: 10))
    }
    func testRecordAcceptedFactsHomeAndFollowUp() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["No open follow-ups."].waitForExistence(timeout: 10))
        capture("Standard Home empty", app)
        begin(app)
        XCTAssertFalse(app.buttons["Save to Post"].isEnabled)
        XCTAssertTrue(app.buttons["Save to Post"].isHittable)
        XCTAssertEqual(app.datePickers.count, 0)
        capture("Standard recording entry", app)
        tap("No answer", app)
        XCTAssertTrue(app.buttons["Save to Post"].isEnabled)
        let followUp = app.switches["Set a follow-up"]
        followUp.tap()
        XCTAssertTrue(app.buttons["Change time"].exists)
        capture("Standard recording follow-up", app)
        tap("Save to Post", app)
        XCTAssertTrue(app.staticTexts["The Post confirmed your Buddy Check."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No answer"].exists)
        XCTAssertTrue(app.staticTexts["Follow-up saved"].exists)
        XCTAssertTrue(app.staticTexts["No phone alert is scheduled."].exists)
        capture("Standard accepted confirmation", app)
        tap("View follow-up", app)
        XCTAssertTrue(app.buttons["Check on this member"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Check on this member"].isHittable)
        capture("Standard follow-up actions", app)
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["The Post confirmed your Buddy Check."].waitForExistence(timeout: 10))
        tap("Back to Home", app)
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
        let recent = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex Example, No answer")).firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No open follow-ups."].exists)
        capture("Standard Home with activity", app)
        recent.tap()
        tap("Correct this check", app)
        tap("We connected", app)
        tap("Save correction", app)
        XCTAssertTrue(app.staticTexts["The Post confirmed your Buddy Check."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["We connected"].exists)
        capture("Standard correction accepted", app)
        tap("Back to Home", app)
        let corrected = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex Example, We connected"))
        XCTAssertTrue(corrected.firstMatch.waitForExistence(timeout: 10)); XCTAssertEqual(corrected.count, 1)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex Example, No answer")).firstMatch.exists)
        app.tabBars.buttons["Follow-ups"].tap()
        let callback = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex Example,")).firstMatch
        XCTAssertTrue(callback.waitForExistence(timeout: 10)); callback.tap()
        tap("Check on this member", app); tap("Record a check", app)
        tap("No contact attempted", app); tap("Save to Post", app)
        XCTAssertTrue(app.staticTexts["The Post confirmed your Buddy Check."].waitForExistence(timeout: 10))
        tap("Back to Home", app)
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
        app.tabBars.buttons["Follow-ups"].tap()
        XCTAssertTrue(app.navigationBars["Your follow-ups"].waitForExistence(timeout: 10))
        app.terminate()
    }
    func testMethodAndNoteSurviveRestartAndDirectCorrection() {
        let app = launch(persist: true)
        begin(app)
        tap("Edit", app)
        XCTAssertTrue(app.datePickers.firstMatch.exists)
        app.segmentedControls.buttons["Text"].tap()
        tap("Done", app)
        tap("I left a message", app)
        tap("Add a note", app)
        let note = app.textFields.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10)); note.tap(); note.typeText("Synthetic note retained after restart.")
        XCTAssertTrue(app.buttons["Save to Post"].isHittable)
        let saveFrame = app.buttons["Save to Post"].frame
        let doneFrame = app.buttons["Done"].frame
        XCTAssertFalse(saveFrame.intersects(doneFrame), "Keyboard dismissal must not cover Save")
        XCTAssertLessThanOrEqual(saveFrame.maxY, app.keyboards.firstMatch.frame.minY)
        capture("Standard note and keyboard", app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Continue with Alex"].waitForExistence(timeout: 15))
        capture("Standard named draft", app)
        tap("Continue with Alex", app)
        XCTAssertTrue(app.staticTexts["Text"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Save to Post"].isEnabled)
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "Synthetic note retained after restart.")
        tap("Save to Post", app)
        XCTAssertTrue(app.staticTexts["The Post confirmed your Buddy Check."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Text · ")).firstMatch.exists)
        tap("Correct this check", app)
        XCTAssertTrue(app.buttons["Save correction"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "Synthetic note retained after restart.")
        tap("We connected", app); tap("Save correction", app)
        XCTAssertTrue(app.staticTexts["The Post confirmed your Buddy Check."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["We connected"].exists)
        tap("Back to Home", app)
        XCTAssertFalse(app.buttons["Continue with Alex"].exists)
        app.terminate()
    }
    func testUncertainSaveRetainsRecoveryAndDoesNotDuplicate() {
        let app = launch(lostResponse: true)
        begin(app); tap("No answer", app); tap("Save to Post", app)
        let pending = app.staticTexts["Submission pending. It may already have been accepted by the Post."]
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["The Post confirmed your Buddy Check."].exists)
        XCTAssertFalse(app.buttons["Save to Post"].exists)
        capture("Standard pending save", app)
        for _ in 0..<3 { app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.staticTexts["Submission pending"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Check on someone, Search the Post member list"].exists)
        capture("Standard Home recovery", app)
        tap("Check submission", app)
        XCTAssertTrue(app.buttons["Check on someone, Search the Post member list"].waitForExistence(timeout: 10))
        let records = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex Example, No answer"))
        XCTAssertTrue(records.firstMatch.waitForExistence(timeout: 10)); XCTAssertEqual(records.count, 1)
        app.terminate()
    }
    func testStaleCorrectionPreservesProposedNote() {
        let app = launch(staleCorrection: true)
        let record = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex Example, No answer")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
        tap("Correct this check", app)
        let note = app.textFields.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10)); note.tap(); note.typeText(" Added by caller.")
        tap("We connected", app); tap("Save correction", app)
        XCTAssertTrue(app.staticTexts["This check changed at the Post"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["The Post confirmed your Buddy Check."].exists)
        tap("Review latest check", app)
        XCTAssertTrue(app.staticTexts["Updated in another session."].waitForExistence(timeout: 10))
        capture("Standard stale correction review", app)
        tap("Continue with my correction", app)
        XCTAssertTrue(app.buttons["Save correction"].waitForExistence(timeout: 10))
        XCTAssertTrue((app.textFields.firstMatch.value as? String)?.contains("Added by caller.") == true)
        tap("Save correction", app)
        XCTAssertTrue(app.staticTexts["The Post confirmed your Buddy Check."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["We connected"].exists)
        app.terminate()
    }
}

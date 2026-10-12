import XCTest

@MainActor final class BuddyChecksUITests: XCTestCase {
    private func restorePrelinkNavigation() throws {
        if (ProcessInfo.processInfo.environment["BUDDY_CHECKS_NATIVE_PRELINK_RESUME"] == "1" || ProcessInfo.processInfo.environment["BUDDY_CHECKS_NATIVE_CONTACT_RETRY"] == "1"), #available(iOS 27.0, *) {
            let service = XCUIDevice.shared.voiceOverService
            if service.isEnabled { try service.disable() }
            XCTAssertFalse(service.isEnabled, "Restore ordinary navigation before this fixture's coordinate tests")
        }
    }
    private func launch(largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BUDDY_CHECKS_TEST_STORE"] = UUID().uuidString
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["Suggest someone"].waitForExistence(timeout: 10))
        return app
    }
    private func visibleAction(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing action: \(label)")
        // A partly covered button may report isHittable while XCTest taps the
        // floating tab/scroll-edge region. Reveal the full body action first.
        if !app.navigationBars.buttons[label].exists {
            let top = app.navigationBars.firstMatch.frame.maxY + 8
            let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 16 : app.frame.maxY - 16
            for _ in 0..<8 {
                let frame = button.frame
                if button.isHittable && frame.minY >= top && frame.maxY <= bottom { break }
                // Full swipes can jump past a large button and oscillate. A
                // measured slow drag brings its center into the visible area.
                let center = (top + bottom) / 2
                let limit = (bottom - top) / 2 - 8
                let distance = max(-limit, min(limit, frame.midY - center))
                let start = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: app.frame.midX, dy: center))
                let end = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: app.frame.midX, dy: center - distance))
                start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            }
            XCTAssertGreaterThanOrEqual(button.frame.minY, top, "Action is covered by navigation: \(label)")
            XCTAssertLessThanOrEqual(button.frame.maxY, bottom, "Action is covered by tabs: \(label)")
        }
        XCTAssertTrue(button.isHittable, "Unreachable action: \(label)")
        return button
    }
    private func tap(_ label: String, in app: XCUIApplication) {
        visibleAction(label, in: app).tap()
    }
    private func evidence(_ name: String, app: XCUIApplication) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name) accessibility tree"; tree.lifetime = .keepAlways; add(tree)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = name; screen.lifetime = .keepAlways; add(screen)
    }

    func testNativeCreationConfirmationCancellation() throws { try nativeCreationConfirmation(largeText: false) }
    func testNativeCreationConfirmationCancellationAtLargestText() throws { try nativeCreationConfirmation(largeText: true) }
    func testNativeRetryCancellationRetainsPending() throws { try nativeCreationConfirmation(largeText: false, retryCancellation: true) }
    func testNativeRetryCancellationRetainsPendingAtLargestText() throws { try nativeCreationConfirmation(largeText: true, retryCancellation: true) }
    private func nativeCreationConfirmation(largeText: Bool, retryCancellation: Bool = false) throws {
        try restorePrelinkNavigation()
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_NATIVE_CONTACTS"] == "1", "Opens but never saves the native editor on the approved simulator.")
        XCTAssertEqual(environment["SIMULATOR_DEVICE_NAME"], "Legion Buddy Checks - iPhone 17 Pro")
        continueAfterFailure = false
        let app = launch(largeText: largeText)
        if retryCancellation {
            let attachment = XCTAttachment(string: try XCTUnwrap(app.launchEnvironment["BUDDY_CHECKS_TEST_STORE"]))
            attachment.name = "Local retry cancellation store"; attachment.lifetime = .keepAlways; add(attachment)
        }
        func openContact(pending: Bool = false) {
            tap("Check on someone", in: app); tap("Robert Miller", in: app)
            tap(pending ? "Phone contact" : "Add to Contacts", in: app)
        }
        openContact(); tap("Create new contact", in: app)
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Robert")).firstMatch.waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Suggest someone"].waitForExistence(timeout: 10)); openContact(pending: true)
        XCTAssertTrue(app.staticTexts["Finish linking your contact"].waitForExistence(timeout: 10))
        tap("Create another contact", in: app)
        XCTAssertTrue(app.staticTexts["Create another contact?"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["A contact may already exist."].exists)
        XCTAssertTrue(app.staticTexts["Choose it from Contacts to avoid a duplicate."].exists)
        evidence("Local duplicate contact confirmation \(largeText ? "largest" : "ordinary")", app: app)
        _ = visibleAction("Cancel", in: app)
        evidence("Local duplicate confirmation actions \(largeText ? "largest" : "ordinary")", app: app)
        tap("Cancel", in: app)
        XCTAssertTrue(app.staticTexts["Finish linking your contact"].exists)
        XCTAssertFalse(app.navigationBars["New Contact"].exists)
        if retryCancellation {
            tap("Create another contact", in: app)
            XCTAssertTrue(app.staticTexts["Create another contact?"].waitForExistence(timeout: 10))
            let sheet = app.scrollViews.containing(.staticText, identifier: "Create another contact?").firstMatch
            let confirm = sheet.buttons["Create another contact"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 10))
            for _ in 0..<8 where !confirm.isHittable || confirm.frame.maxY > app.frame.maxY - 32 { sheet.swipeUp() }
            XCTAssertTrue(confirm.isHittable); confirm.tap()
            XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Robert")).firstMatch.waitForExistence(timeout: 10))
            app.buttons["Cancel"].tap()
            if app.buttons["Discard Changes"].waitForExistence(timeout: 2) { app.buttons["Discard Changes"].tap() }
            evidence("Local cancelled retry retains pending \(largeText ? "largest" : "ordinary")", app: app)
            XCTAssertTrue(app.staticTexts["Finish linking your contact"].waitForExistence(timeout: 5), "Cancelling this attempt does not resolve the earlier interrupted attempt")
            if environment["BUDDY_CHECKS_NATIVE_CONTACT_DISMISSAL"] == "1" {
                // Keep the immediate capture above. A bounded later observation
                // distinguishes a transition frame from persistent chrome damage.
                XCTAssertTrue(app.navigationBars["New Contact"].waitForNonExistence(timeout: 5))
                let settled = expectation(description: "Observe completed native dismissal")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { settled.fulfill() }
                wait(for: [settled], timeout: 3)
                let tabs = app.tabBars.firstMatch
                XCTAssertTrue(tabs.waitForExistence(timeout: 5))
                for label in ["Home", "Follow-ups"] {
                    let button = tabs.buttons[label]
                    XCTAssertTrue(button.isHittable)
                    XCTAssertGreaterThan(button.frame.minY, app.navigationBars.firstMatch.frame.maxY)
                    XCTAssertLessThanOrEqual(button.frame.maxY, app.frame.maxY)
                }
                evidence("Local settled retry dismissal \(largeText ? "largest" : "ordinary")", app: app)
                tabs.buttons["Follow-ups"].tap()
                XCTAssertTrue(app.navigationBars["Follow-ups"].waitForExistence(timeout: 5))
                tabs.buttons["Home"].tap()
                XCTAssertTrue(app.navigationBars["Phone contact"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["Finish linking your contact"].exists)
                evidence("Local Contacts after tab return \(largeText ? "largest" : "ordinary")", app: app)
            }
            app.terminate(); app.launch()
            XCTAssertTrue(app.buttons["Suggest someone"].waitForExistence(timeout: 10)); openContact(pending: true)
            XCTAssertTrue(app.staticTexts["Finish linking your contact"].waitForExistence(timeout: 10))
            tap("Create another contact", in: app)
            XCTAssertTrue(app.staticTexts["Choose it from Contacts to avoid a duplicate."].waitForExistence(timeout: 10))
            evidence("Local retry cancellation guard restored", app: app)
            tap("Cancel", in: app)
        }
    }
    func testSuggestionNavigationSelectionAndExhaustion() throws {
        let app = launch()
        tap("Suggest someone", in: app)
        let bar = app.navigationBars["Suggestions"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        evidence("Suggestions", app: app)
        XCTAssertFalse(app.buttons["Snooze for 7 days"].exists)
        XCTAssertFalse(app.buttons["Skip for 7 days"].exists)
        XCTAssertTrue(bar.buttons["Refresh suggestions"].exists)
        XCTAssertTrue(bar.buttons["Refresh suggestions"].isHittable)
        XCTAssertEqual(bar.buttons.count, 2, "Native Back and Refresh should both be accessible")
        tap("Check on Elena", in: app)
        XCTAssertTrue(app.buttons["Simulate call with Elena"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue with Elena"].exists)
        let back = app.navigationBars["Buddy Check"].buttons.element(boundBy: 0)
        XCTAssertTrue(back.isHittable); back.tap()
        tap("Someone else", in: app)
        XCTAssertTrue(app.buttons["Check on Robert"].waitForExistence(timeout: 5))
        tap("Someone else", in: app)
        XCTAssertTrue(app.buttons["Check on James"].waitForExistence(timeout: 5))
        tap("Someone else", in: app)
        XCTAssertTrue(app.staticTexts["You've seen the suggestions"].waitForExistence(timeout: 5))
        tap("Refresh suggestions", in: app)
        XCTAssertTrue(app.buttons["Start again"].exists)
        tap("Start again", in: app)
        XCTAssertTrue(app.buttons["Check on Elena"].exists)
        bar.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Record a check"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue with Elena"].exists)
        tap("Recent checks, No checks recorded yet", in: app)
        XCTAssertTrue(app.staticTexts["Your saved checks will appear here."].waitForExistence(timeout: 5))
    }

    func testInterruptedManualCheckCorrectionAndSingleRecord() throws {
        let app = launch()
        tap("Record a check", in: app)
        tap("Robert Miller", in: app)
        tap("Text message", in: app)
        tap("Continue", in: app)
        tap("No reply", in: app)
        app.terminate(); app.launch()
        tap("Continue with Robert", in: app)
        XCTAssertTrue(app.buttons["No reply"].isSelected)
        XCTAssertFalse(app.buttons["We exchanged messages"].isSelected)
        evidence("Restored outcome", app: app)
        tap("Save without follow-up", in: app)
        XCTAssertTrue(app.staticTexts["No reply"].waitForExistence(timeout: 5))
        tap("Correct this check", in: app)
        tap("We exchanged messages", in: app)
        tap("Save correction", in: app)
        XCTAssertTrue(app.staticTexts["We exchanged messages"].waitForExistence(timeout: 5))
        tap("Back to Home", in: app)
        tap("Recent checks, 1 saved on this iPhone", in: app)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Robert Miller, We exchanged messages")).count, 1)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Recent checks, 1 saved on this iPhone"].exists)
        XCTAssertFalse(app.buttons["Continue with Robert"].exists)
    }

    func testNativeContactReviewCancellation() throws { try nativeContactReviewCancellation(largeText: false) }
    func testLinkedLocalContactOpensDirectly() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_NATIVE_CONTACTS"] == "1", "Reads the existing approved synthetic Robert link; never saves Contacts.")
        XCTAssertEqual(environment["SIMULATOR_DEVICE_NAME"], "Legion Buddy Checks - iPhone 17 Pro")
        continueAfterFailure = false
        let app = XCUIApplication()
        for large in [false, true] {
            app.launchArguments = large ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : []
            app.launch()
            tap("Check on someone", in: app); tap("Robert Miller", in: app); tap("Phone contact", in: app)
            XCTAssertTrue(app.staticTexts["Post contact details"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Review Post updates"].exists)
            XCTAssertFalse(app.buttons["Use home label"].exists)
            XCTAssertFalse(app.buttons["Choose existing contact"].exists)
            XCTAssertFalse(app.buttons["Create another contact"].exists)
            evidence("Direct local contact \(large ? "largest" : "ordinary")", app: app)
            let mainAction = app.buttons["Save changes"].exists ? "Save changes" : "Open contact"
            _ = visibleAction(mainAction, in: app)
            evidence("Direct local contact main action \(large ? "largest" : "ordinary")", app: app)
            // Native navigation exposes recovery only when requested.
            app.buttons["Contact options"].tap()
            XCTAssertTrue(app.buttons["Choose existing contact"].waitForExistence(timeout: 5))
            evidence("Contact options \(large ? "largest" : "ordinary")", app: app)
            app.terminate()
        }
        app.launchArguments = []; app.launch(); app.terminate()
    }
    func testNativeContactReviewCancellationAtLargestText() throws { try nativeContactReviewCancellation(largeText: true) }
    private func nativeContactReviewCancellation(largeText: Bool) throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_NATIVE_CONTACTS"] == "1", "Read-only review of the already-shared synthetic contact on its approved simulator.")
        XCTAssertEqual(environment["SIMULATOR_DEVICE_NAME"], "Legion Buddy Checks - iPhone 17 Pro")
        continueAfterFailure = false
        let app = launch(largeText: largeText)
        tap("Check on someone", in: app); tap("Robert Miller", in: app)
        tap("Add to Contacts", in: app)
        evidence("Local Contacts before picker \(largeText ? "largest" : "ordinary")", app: app)
        tap("Choose existing contact", in: app)
        // The retained simulator now has several synthetic cards. Search keeps
        // the intended row above the picker edge at either text size.
        let search = app.searchFields["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Robert Miller")
        // The search overlay retains the underlying list in its AX tree. Select
        // the visible result, not the first cached offscreen cell with this name.
        let names = app.staticTexts.matching(identifier: "Robert Miller")
        let visibleResult = NSPredicate { _, _ in names.allElementsBoundByIndex.contains { $0.isHittable } }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visibleResult, object: nil)], timeout: 10), .completed)
        let row = try XCTUnwrap(names.allElementsBoundByIndex.first { $0.isHittable })
        row.tap()
        XCTAssertTrue(app.buttons["Cancel review"].waitForExistence(timeout: 10))
        evidence("Local Contacts native review \(largeText ? "largest" : "ordinary")", app: app)
        let name = app.staticTexts["Robert Miller"]
        let nameVisible = NSPredicate { _, _ in
            name.exists && name.frame.minY >= app.navigationBars.firstMatch.frame.maxY + 8
                && name.frame.maxY < app.tabBars.firstMatch.frame.minY
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: nameVisible, object: nil)], timeout: 5), .completed,
                       "Opening review must reveal the shared person card above the working details")
        // Never press native Save or Link: review cancellation must not create an association.
        tap("Cancel review", in: app)
        XCTAssertTrue(app.buttons["Create new contact"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Open contact"].exists)
        evidence("Local Contacts cancelled review \(largeText ? "largest" : "ordinary")", app: app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: nameVisible, object: nil)], timeout: 5), .completed,
                       "Cancelling review must return to the shared person card")
        app.terminate(); app.launch()
        tap("Check on someone", in: app); tap("Robert Miller", in: app)
        tap("Add to Contacts", in: app)
        XCTAssertTrue(app.buttons["Create new contact"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Open contact"].exists)
    }

    func testContactsScreenAccessibility() throws {
        let app = launch()
        tap("Check on someone", in: app)
        tap("Robert Miller", in: app)
        tap("Add to Contacts", in: app)
        evidence("Contacts", app: app)
        XCTAssertTrue(app.navigationBars["Phone contact"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Create new contact"].exists)
        XCTAssertTrue(app.buttons["Choose existing contact"].exists)
        for field in ["Company, American Legion Post 165", "Phone number, +12025550101", "Email address, robert.miller@example.org"] {
            XCTAssertTrue(app.staticTexts[field].exists, "Missing labelled contact field: \(field)")
        }
        app.scrollViews.firstMatch.swipeUp()
        evidence("Contacts lower content", app: app)
    }
    func testLargestTextContactsAndSuggestions() throws {
        let app = launch(largeText: true)
        tap("Check on someone", in: app)
        tap("Robert Miller", in: app)
        tap("Add to Contacts", in: app)
        XCTAssertTrue(app.navigationBars["Phone contact"].waitForExistence(timeout: 5))
        evidence("Largest text Contacts top", app: app)
        _ = visibleAction("Choose existing contact", in: app)
        evidence("Largest text Contacts actions", app: app)
        let footer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "This saves a personal copy")).firstMatch
        for _ in 0..<6 where footer.frame.maxY > app.tabBars.firstMatch.frame.minY - 16 {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertLessThanOrEqual(footer.frame.maxY, app.tabBars.firstMatch.frame.minY - 16,
            "The final line must scroll above the tab controls")
        evidence("Largest text Contacts bottom", app: app)
        app.terminate()
        let suggestions = launch(largeText: true)
        tap("Suggest someone", in: suggestions)
        evidence("Largest text Suggestions top", app: suggestions)
        tap("Someone else", in: suggestions)
        XCTAssertTrue(suggestions.staticTexts["Robert Miller"].isHittable,
            "Changing the suggestion should restore the new person's name onscreen")
        evidence("Largest text Suggestions changed person", app: suggestions)
    }

    func testVoiceOverContactsFieldsAndActions() throws {
        let app = launch()
        tap("Check on someone", in: app)
        tap("Robert Miller", in: app)
        tap("Add to Contacts", in: app)
        try checkVoiceOver(name: "Contacts", required: ["robert miller", "company",
            "american legion post 165", "phone number", "email address", "mailing address",
            "create new contact", "choose existing contact"])
    }

    func testVoiceOverLargestTextContactsFieldsAndActions() throws {
        let app = launch(largeText: true)
        tap("Check on someone", in: app)
        tap("Robert Miller", in: app)
        tap("Add to Contacts", in: app)
        XCTAssertTrue(app.navigationBars["Phone contact"].waitForExistence(timeout: 5))
        try checkVoiceOver(name: "Largest text Contacts", required: ["robert miller", "company",
            "american legion post 165", "phone number", "email address", "mailing address",
            "create new contact", "choose existing contact"])
        evidence("Largest text Contacts after VoiceOver", app: app)
    }

    func testVoiceOverSuggestionFocus() throws {
        let app = launch()
        tap("Suggest someone", in: app)
        try checkVoiceOver(name: "Suggestions", required: ["refresh", "elena davis",
            "check on elena", "someone else"])
    }

    private func checkVoiceOver(name: String, required: [String]) throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("VoiceOver test service needs iOS 27 or later.") }
        let service = XCUIDevice.shared.voiceOverService
        let wasEnabled = service.isEnabled
        defer { if !wasEnabled { try? service.disable() } }
        do { try service.enable() }
        catch { throw XCTSkip("VoiceOver service could not start on this test device: \(error)") }
        var utterances: [String] = [try service.currentSpeech().utterance]
        for _ in 0..<32 {
            let output = try service.moveForward()
            if utterances.last == output.utterance { break }
            utterances.append(output.utterance)
        }
        let transcript = XCTAttachment(string: utterances.joined(separator: "\n"))
        transcript.name = "VoiceOver \(name) focus"; transcript.lifetime = .keepAlways; add(transcript)
        let speech = utterances.joined(separator: " ").lowercased()
        for label in required {
            XCTAssertTrue(speech.contains(label), "VoiceOver did not reach \(label)")
        }
    }

}

/// Run separately from workflow regressions. This suite intentionally preserves
/// unfiltered SDK findings; see docs/NATIVE_UI_REVIEW.md for current failures.
@MainActor final class RawAccessibilityAuditTests: XCTestCase {
    private func contacts() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BUDDY_CHECKS_TEST_STORE"] = UUID().uuidString
        app.launch()
        app.buttons["Check on someone"].tap()
        app.buttons["Robert Miller"].tap()
        app.buttons["Add to Contacts"].tap()
        XCTAssertTrue(app.navigationBars["Phone contact"].waitForExistence(timeout: 5))
        return app
    }
    func testContactsRawAudit() throws {
        let app = contacts()
        try audit(app, position: "initial")
    }
    func testContactsActionsRawAudit() throws {
        let app = contacts()
        app.scrollViews.firstMatch.swipeUp()
        let create = app.buttons["Create new contact"]
        let choose = app.buttons["Choose existing contact"]
        XCTAssertTrue(create.isHittable && choose.isHittable)
        XCTAssertLessThan(choose.frame.maxY, app.tabBars.firstMatch.frame.minY)
        try audit(app, position: "actions")
    }
    func testContactsFooterRawAudit() throws {
        try audit(contactsWithVisibleFooter(), position: "footer fully visible")
    }
    func testContactsFooterContrastOnlyDiagnostic() throws {
        // Diagnostic companion, never a replacement for the full audits above.
        try audit(contactsWithVisibleFooter(), position: "footer contrast only", types: .contrast)
    }
    private func contactsWithVisibleFooter() -> XCUIApplication {
        let app = contacts()
        let footer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "This saves a personal copy")).firstMatch
        for _ in 0..<4 where footer.frame.maxY > app.tabBars.firstMatch.frame.minY - 16 {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(footer.isHittable)
        XCTAssertGreaterThanOrEqual(footer.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(footer.frame.maxY, app.tabBars.firstMatch.frame.minY - 16)
        return app
    }
    private func audit(_ app: XCUIApplication, position: String, types: XCUIAccessibilityAuditType = .all) throws {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Before raw audit: \(position)"; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Before raw audit tree: \(position)"; tree.lifetime = .keepAlways; add(tree)
        try app.performAccessibilityAudit(for: types) { issue in
            let detail = XCTAttachment(string: """
            Position: \(position)
            Type: \(issue.auditType.rawValue)
            Label: \(issue.element?.label ?? "No element")
            Frame: \(String(describing: issue.element?.frame))
            Summary: \(issue.compactDescription)
            Detail: \(issue.detailedDescription)
            """)
            detail.name = "Raw audit element details"; detail.lifetime = .keepAlways; self.add(detail)
            return false // Record every SDK finding; this observer suppresses nothing.
        }
    }
}

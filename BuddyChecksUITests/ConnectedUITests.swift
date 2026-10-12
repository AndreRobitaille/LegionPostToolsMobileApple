import XCTest

@MainActor final class ConnectedUITests: XCTestCase {
    private func restorePrelinkNavigation() throws {
        if (ProcessInfo.processInfo.environment["BUDDY_CHECKS_NATIVE_PRELINK_RESUME"] == "1" || ProcessInfo.processInfo.environment["BUDDY_CHECKS_NATIVE_CONTACT_RETRY"] == "1" || ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONTACT_SAVE_REJECTION"] == "1"), #available(iOS 27.0, *) {
            let service = XCUIDevice.shared.voiceOverService
            if service.isEnabled { try service.disable() }
            XCTAssertFalse(service.isEnabled, "Restore ordinary navigation before this fixture's coordinate tests")
        }
    }
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(largeText: Bool = false, lostResponse: Bool = false, export: Bool = false, paused: Bool = false, staleCorrection: Bool = false, changedFollowUp: Bool = false, changedExport: Bool = false, changedMember: Bool = false, randomSuggestions: Bool = false, nativeContact: String? = nil, nativeCompanyReview: String? = nil, rejectContactSave: Bool = false, nativeCreation: Bool = false, nativeCreationStore: String? = nil, nativeCreationInterruption: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BUDDY_CHECKS_TEST_STORE"] = UUID().uuidString
        if nativeCreation, let value = nativeCreationStore, let id = UUID(uuidString: value) {
            app.launchEnvironment["BUDDY_CHECKS_TEST_STORE"] = id.uuidString
        }
        app.launchEnvironment["BUDDY_CHECKS_CONNECTED_FIXTURE"] = "1"
        if lostResponse { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_LOST_RESPONSE"] = "1" }
        if export { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_EXPORT"] = "1" }
        if paused { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_PAUSED"] = "1" }
        if staleCorrection { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_STALE_CORRECTION"] = "1" }
        if changedFollowUp { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_CHANGED_FOLLOW_UP"] = "1" }
        if changedExport { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_CHANGED_EXPORT"] = "1" }
        if changedMember { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_CHANGED_MEMBER"] = "1" }
        if randomSuggestions { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_RANDOM_SUGGESTIONS"] = "1" }
        if let nativeContact { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_NATIVE_CONTACT"] = nativeContact }
        if let nativeCompanyReview { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_NATIVE_COMPANY_REVIEW"] = nativeCompanyReview }
        if rejectContactSave { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_REJECT_CONTACT_SAVE"] = "1" }
        if nativeCreation { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_NATIVE_CREATION"] = "1" }
        if let nativeCreationInterruption { app.launchEnvironment["BUDDY_CHECKS_CONNECTED_CREATION_INTERRUPTION"] = nativeCreationInterruption }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10))
        return app
    }
    func testNativeSavedCardInterruptionAndRecovery() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_NATIVE_PRELINK_SAVE"] == "1", "Creates one separate synthetic card, then terminates before its app link is saved.")
        XCTAssertEqual(environment["SIMULATOR_DEVICE_NAME"], "Legion Buddy Checks - iPhone 17 Pro")
        let store = try XCTUnwrap(environment["BUDDY_CHECKS_NATIVE_PRELINK_STORE"])
        XCTAssertNotNil(UUID(uuidString: store))
        let app = launch(export: true, nativeCreation: true, nativeCreationStore: store, nativeCreationInterruption: "arm")
        openPrelinkContact(app)
        XCTAssertFalse(app.buttons["Review Post updates"].exists)
        XCTAssertFalse(app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].exists)
        tap("Create new contact", app: app)
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Taylor")).firstMatch.waitForExistence(timeout: 10))
        capture("Native recovery card before Save", app: app)
        let save = app.navigationBars["New Contact"].buttons.matching(NSPredicate(format: "label == 'Done' OR label == 'Save'")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10)); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.navigationBars["Saved before link test hold"].waitForExistence(timeout: 10))
        capture("Native card saved before app completion", app: app)
        app.terminate()
        app.launchEnvironment["BUDDY_CHECKS_CONNECTED_CREATION_INTERRUPTION"] = "resume"
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        restartPrelinkContact(app)
        XCTAssertTrue(app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Review Post updates"].exists)
        recoverSavedPrelinkContact(app)
        app.terminate(); app.launchArguments = []
        restartPrelinkContact(app)
        verifyPrelinkRestoration(app)
    }
    func testNativeSavedCardRecoveryContinuationAtLargestText() throws {
        try restorePrelinkNavigation()
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_NATIVE_PRELINK_RESUME"] == "1", "Continues the recorded saved card without another native creation.")
        XCTAssertEqual(environment["SIMULATOR_DEVICE_NAME"], "Legion Buddy Checks - iPhone 17 Pro")
        let store = try XCTUnwrap(environment["BUDDY_CHECKS_NATIVE_PRELINK_STORE"])
        XCTAssertNotNil(UUID(uuidString: store))
        let app = launch(largeText: true, export: true, nativeCreation: true, nativeCreationStore: store, nativeCreationInterruption: "resume")
        openPrelinkContact(app)
        if app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].exists {
            recoverSavedPrelinkContact(app)
            app.terminate(); restartPrelinkContact(app)
        }
        tap("Create new contact", app: app)
        dismissDuplicateContactConfirmation(app)
        XCTAssertFalse(app.navigationBars["New Contact"].exists)
        verifyPrelinkRestoration(app)
        // Confirming must wait for sheet dismissal before opening ContactsUI.
        // Cancel the form: no second native Save is submitted.
        tap("Create new contact", app: app)
        XCTAssertTrue(app.staticTexts["Create another contact?"].waitForExistence(timeout: 10))
        tap("Create another contact", app: app)
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Taylor")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        if app.buttons["Discard Changes"].waitForExistence(timeout: 2) { app.buttons["Discard Changes"].tap() }
        XCTAssertTrue(app.staticTexts["Contact creation cancelled."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Post contact details"].exists || app.buttons["Review Post updates"].exists)
        app.terminate(); restartPrelinkContact(app); verifyPrelinkRestoration(app)
    }
    func testNativeDuplicateContactConfirmationVoiceOver() throws {
        try restorePrelinkNavigation()
        guard #available(iOS 27.0, *) else { throw XCTSkip("Requires the native VoiceOver test service.") }
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_NATIVE_PRELINK_RESUME"] == "1", "Reads the recorded recovery fixture; no native save.")
        XCTAssertEqual(environment["SIMULATOR_DEVICE_NAME"], "Legion Buddy Checks - iPhone 17 Pro")
        let store = try XCTUnwrap(environment["BUDDY_CHECKS_NATIVE_PRELINK_STORE"])
        let app = launch(largeText: true, export: true, nativeCreation: true, nativeCreationStore: store, nativeCreationInterruption: "resume")
        openPrelinkContact(app); tap("Create new contact", app: app)
        XCTAssertTrue(app.staticTexts["Create another contact?"].waitForExistence(timeout: 10))
        let service = XCUIDevice.shared.voiceOverService
        addTeardownBlock {
            try await MainActor.run { try XCUIDevice.shared.voiceOverService.disable() }
        }
        try service.enable()
        var speech = [try service.currentSpeech().utterance]
        for _ in 0..<16 {
            if speech.joined(separator: " ").contains("Create another contact Button") && speech.joined(separator: " ").contains("avoid a duplicate") { break }
            speech.append(try service.moveForward().utterance)
        }
        let transcript = speech.joined(separator: "\n")
        let attachment = XCTAttachment(string: transcript)
        attachment.name = "Duplicate contact confirmation VoiceOver"; attachment.lifetime = .keepAlways; add(attachment)
        // Disable before assertions: XCTest can abort a failing case before Swift defer.
        try service.disable()
        XCTAssertTrue(transcript.contains("A contact may already exist."))
        XCTAssertTrue(transcript.contains("Choose it from Contacts to avoid a duplicate."))
        XCTAssertTrue(transcript.contains("Create another contact Button"))
        XCTAssertTrue(transcript.contains("Cancel"))
        tap("Cancel", app: app)
        XCTAssertTrue(app.staticTexts["Post contact details"].exists || app.buttons["Review Post updates"].exists)
        XCTAssertFalse(app.navigationBars["New Contact"].exists)
    }
    private func dismissDuplicateContactConfirmation(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Create another contact?"].waitForExistence(timeout: 10))
        let message = app.staticTexts["Choose it from Contacts to avoid a duplicate."]
        XCTAssertTrue(message.exists && app.staticTexts["A contact may already exist."].exists)
        capture("Duplicate contact confirmation explanation", app: app)
        for _ in 0..<16 where !app.buttons["Cancel"].isHittable { scrollPage(app) }
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        capture("Duplicate contact confirmation actions", app: app)
        app.buttons["Cancel"].tap()
    }
    private func openPrelinkContact(_ app: XCUIApplication) {
        tap("Suggest someone, From Post records", app: app); tap("Check on Taylor", app: app); tap("Phone contact", app: app)
    }
    private func restartPrelinkContact(_ app: XCUIApplication) {
        app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10)); openPrelinkContact(app)
    }
    private func recoverSavedPrelinkContact(_ app: XCUIApplication) {
        capture("Saved card still needs linking after restart", app: app)
        tap("Create new contact", app: app)
        XCTAssertTrue(app.staticTexts["Choose it from Contacts to avoid a duplicate."].waitForExistence(timeout: 10))
        capture("Saved card duplicate creation confirmation", app: app)
        dismissDuplicateContactConfirmation(app)
        tap("Choose existing contact", app: app)
        let search = app.searchFields["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Taylor Recovery")
        let rows = app.cells.containing(.staticText, identifier: "Taylor Recovery")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10)); XCTAssertEqual(rows.count, 1)
        capture("One saved recovery card in native picker", app: app)
        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["Use this contact"].waitForExistence(timeout: 10) || app.staticTexts["This contact is up to date."].exists)
        XCTAssertFalse(app.buttons["Save changes"].exists)
        capture("Saved card matching Post review", app: app)
        tap("Use this contact", app: app)
        XCTAssertTrue(app.staticTexts["Contact linked."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].exists)
        capture("Saved card linked without creating another", app: app)
    }
    private func verifyPrelinkRestoration(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Post contact details"].waitForExistence(timeout: 10) || app.buttons["Review Post updates"].exists)
        XCTAssertFalse(app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].exists)
        openContactReview(app)
        XCTAssertTrue(app.buttons["Use this contact"].waitForExistence(timeout: 10) || app.staticTexts["This contact is up to date."].exists)
        XCTAssertFalse(app.buttons["Save changes"].exists)
        capture("Recovered saved-card link survives restart", app: app)
        tap("Cancel review", app: app)
    }
    func testNativeCreationCancellationAndInterruption() throws { try nativeCreationCancellationAndInterruption() }
    func testNativeRetryCancellationRetainsPending() throws { try nativeCreationCancellationAndInterruption(retryCancellation: true) }
    func testNativeRetryCancellationRetainsPendingAtLargestText() throws { try nativeCreationCancellationAndInterruption(largeText: true, retryCancellation: true) }
    private func nativeCreationCancellationAndInterruption(largeText: Bool = false, retryCancellation: Bool = false) throws {
        try restorePrelinkNavigation()
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_NATIVE_CONTACT_CREATION"] == "1", "Uses the approved simulator's native editor and isolated protected storage.")
        XCTAssertEqual(environment["SIMULATOR_DEVICE_NAME"], "Legion Buddy Checks - iPhone 17 Pro")
        let app = launch(largeText: largeText, export: true, nativeCreation: true)
        let store = XCTAttachment(string: try XCTUnwrap(app.launchEnvironment["BUDDY_CHECKS_TEST_STORE"]))
        store.name = "Native creation isolated store"; store.lifetime = .keepAlways; add(store)
        func openContact() {
            tap("Suggest someone, From Post records", app: app); tap("Check on Alex", app: app); tap("Phone contact", app: app)
        }
        func restart() {
            app.terminate(); app.launch()
            XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10)); openContact()
        }
        openContact(); tap("Create new contact", app: app)
        XCTAssertTrue(app.navigationBars["New Contact"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Alex")).firstMatch.waitForExistence(timeout: 10))
        capture("Connected native creation form", app: app)
        app.buttons["Cancel"].tap()
        if app.buttons["Discard Changes"].waitForExistence(timeout: 2) { app.buttons["Discard Changes"].tap() }
        XCTAssertTrue(app.staticTexts["Contact creation cancelled."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].exists)
        capture("Connected native creation cancelled", app: app)
        tap("Create new contact", app: app)
        XCTAssertTrue(app.navigationBars["New Contact"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        // Interrupt before native Save; the protected pending marker must survive.
        restart()
        XCTAssertTrue(app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].waitForExistence(timeout: 10))
        capture("Connected creation pending after restart", app: app)
        tap("Create new contact", app: app)
        XCTAssertTrue(app.buttons["Create another contact"].waitForExistence(timeout: 5))
        capture("Connected creation requires duplicate confirmation", app: app)
        dismissDuplicateContactConfirmation(app)
        XCTAssertTrue(app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].exists)
        if retryCancellation {
            tap("Create new contact", app: app)
            XCTAssertTrue(app.staticTexts["Create another contact?"].waitForExistence(timeout: 10))
            tap("Create another contact", app: app)
            XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Alex")).firstMatch.waitForExistence(timeout: 10))
            app.buttons["Cancel"].tap()
            if app.buttons["Discard Changes"].waitForExistence(timeout: 2) { app.buttons["Discard Changes"].tap() }
            XCTAssertTrue(app.staticTexts["Contact creation cancelled."].waitForExistence(timeout: 10))
            capture("Connected cancelled retry retains pending \(largeText ? "largest" : "ordinary")", app: app)
            XCTAssertTrue(app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].waitForExistence(timeout: 5), "Cancelling this attempt does not resolve the earlier interrupted attempt")
            restart()
            XCTAssertTrue(app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].waitForExistence(timeout: 10))
            tap("Create new contact", app: app)
            XCTAssertTrue(app.staticTexts["Choose it from Contacts to avoid a duplicate."].waitForExistence(timeout: 10))
            capture("Connected retry cancellation guard restored", app: app)
            dismissDuplicateContactConfirmation(app)
        }
    }
    func testNativeCreationFormAtLargestTextCancellation() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_NATIVE_CONTACT_CREATION"] == "1", "Uses the approved simulator native editor without saving a contact.")
        XCTAssertEqual(environment["SIMULATOR_DEVICE_NAME"], "Legion Buddy Checks - iPhone 17 Pro")
        let app = launch(largeText: true, export: true, nativeCreation: true)
        tap("Suggest someone, From Post records", app: app); tap("Check on Alex", app: app); tap("Phone contact", app: app)
        tap("Create new contact", app: app)
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Alex")).firstMatch.waitForExistence(timeout: 10))
        capture("Connected native creation form largest", app: app)
        app.buttons["Cancel"].tap()
        if app.buttons["Discard Changes"].waitForExistence(timeout: 2) { app.buttons["Discard Changes"].tap() }
        XCTAssertTrue(app.staticTexts["Contact creation cancelled."].waitForExistence(timeout: 10))
        capture("Connected native creation cancelled largest", app: app)
        let result = app.staticTexts["Contact creation cancelled."]
        let visible = NSPredicate { _, _ in
            result.exists && result.frame.minY >= app.navigationBars.firstMatch.frame.maxY
                && result.frame.maxY < app.frame.maxY
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: nil)], timeout: 5), .completed,
                       "The creation result must return into view after the native editor closes")
        if #available(iOS 27.0, *) {
            let service = XCUIDevice.shared.voiceOverService; let wasEnabled = service.isEnabled
            defer { if !wasEnabled { try? service.disable() } }
            try service.enable()
            var speech = [try service.currentSpeech().utterance]
            for _ in 0..<16 {
                if speech.joined(separator: " ").lowercased().contains("contact creation cancelled") { break }
                speech.append(try service.moveForward().utterance)
            }
            let transcript = speech.joined(separator: "\n")
            let attachment = XCTAttachment(string: transcript)
            attachment.name = "Native creation cancellation VoiceOver"; attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertTrue(transcript.lowercased().contains("alex example"))
            XCTAssertTrue(transcript.lowercased().contains("contact creation cancelled"))
        }
        XCTAssertFalse(app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].exists)
    }
    func testNativeCreatedContactRestoration() throws {
        try restorePrelinkNavigation()
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_NATIVE_CONTACT_CREATION_RESTORE"] == "1", "Read-only continuation of the already-created synthetic contact.")
        XCTAssertEqual(environment["SIMULATOR_DEVICE_NAME"], "Legion Buddy Checks - iPhone 17 Pro")
        XCTAssertNotNil(environment["BUDDY_CHECKS_NATIVE_CREATION_STORE"].flatMap(UUID.init(uuidString:)))
        let app = launch(export: true, nativeCreation: true, nativeCreationStore: environment["BUDDY_CHECKS_NATIVE_CREATION_STORE"])
        tap("Suggest someone, From Post records", app: app); tap("Check on Alex", app: app); tap("Phone contact", app: app)
        XCTAssertTrue(app.staticTexts["Post contact details"].waitForExistence(timeout: 10) || app.buttons["Review Post updates"].exists)
        XCTAssertFalse(app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].exists)
        openContactReview(app)
        XCTAssertTrue(app.buttons["Use this contact"].waitForExistence(timeout: 10) || app.staticTexts["This contact is up to date."].exists)
        XCTAssertFalse(app.buttons["Save changes"].exists)
        capture("Existing created card read-only verification", app: app)
        tap("Cancel review", app: app)
        tap("Create new contact", app: app)
        dismissDuplicateContactConfirmation(app)
        XCTAssertTrue(app.staticTexts["Post contact details"].exists || app.buttons["Review Post updates"].exists)
        XCTAssertFalse(app.navigationBars["New Contact"].exists)
    }
    func testNativeCreationSavesManagedEmailAndRestoresAfterUpdate() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_NATIVE_CONTACT_CREATION_SAVE"] == "1", "Creates and retains one synthetic Alex card on the approved simulator.")
        XCTAssertEqual(environment["SIMULATOR_DEVICE_NAME"], "Legion Buddy Checks - iPhone 17 Pro")
        XCTAssertNotNil(environment["BUDDY_CHECKS_NATIVE_CREATION_STORE"].flatMap(UUID.init(uuidString:)))
        let app = launch(export: true, nativeCreation: true, nativeCreationStore: environment["BUDDY_CHECKS_NATIVE_CREATION_STORE"])
        let attachment = XCTAttachment(string: try XCTUnwrap(app.launchEnvironment["BUDDY_CHECKS_TEST_STORE"]))
        attachment.name = "Saved native creation isolated store"; attachment.lifetime = .keepAlways; add(attachment)
        func openContact() {
            tap("Suggest someone, From Post records", app: app); tap("Check on Alex", app: app); tap("Phone contact", app: app)
        }
        func restart(update: Bool) {
            app.terminate()
            app.launchEnvironment["BUDDY_CHECKS_CONNECTED_CREATION_EMAIL_UPDATE"] = update ? "1" : nil
            app.launch()
            XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10)); openContact()
            XCTAssertTrue(app.staticTexts["Post contact details"].waitForExistence(timeout: 10) || app.buttons["Review Post updates"].exists)
            XCTAssertFalse(app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].exists)
        }
        func updateEmail(current: String) {
            openContactReview(app)
            XCTAssertTrue(app.staticTexts["Current: \(current)"].waitForExistence(timeout: 10))
            // A copied value must be replaced using its retained ID, not appended.
            XCTAssertFalse(app.switches["Add Post email"].exists)
            let choice = app.switches.matching(identifier: "Use Post email").firstMatch
            XCTAssertTrue(choice.exists); XCTAssertEqual(choice.value as? String, "0")
            choice.tap(); XCTAssertEqual(choice.value as? String, "1")
            capture("Created contact owned email review", app: app)
            tap("Save changes", app: app)
            XCTAssertTrue(app.staticTexts["Contact updated."].waitForExistence(timeout: 10))
        }
        openContact()
        // A rerun against an already-consumed store must stop before another create.
        XCTAssertFalse(app.buttons["Review Post updates"].exists)
        XCTAssertFalse(app.staticTexts["A contact may already have been saved. Choose it below to finish linking."].exists)
        tap("Create new contact", app: app)
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Alex")).firstMatch.waitForExistence(timeout: 10))
        capture("Connected native editor before accepted creation", app: app)
        let save = app.navigationBars["New Contact"].buttons.matching(NSPredicate(format: "label == 'Done' OR label == 'Save'")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10)); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.staticTexts["Contact saved."].waitForExistence(timeout: 10))
        capture("Connected native creation saved", app: app)
        restart(update: true); updateEmail(current: "alex@example.test")
        restart(update: false); updateEmail(current: "alex.updated@example.test")
        restart(update: false)
        openContactReview(app)
        XCTAssertTrue(app.buttons["Use this contact"].waitForExistence(timeout: 10) || app.staticTexts["This contact is up to date."].exists)
        XCTAssertFalse(app.buttons["Save changes"].exists)
        capture("Created native card restored without new fields", app: app)
        tap("Cancel review", app: app)
    }
    func testConnectedContactSaveRejection() throws { try contactSaveRejection(largeText: false) }
    func testConnectedNativeContactSaveRejection() throws { try contactSaveRejection(largeText: false, nativeRejection: true) }
    func testConnectedContactSaveRejectionAtLargestText() throws { try contactSaveRejection(largeText: true) }
    func testConnectedContactSaveRejectionVoiceOver() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Requires native VoiceOver test service") }
        try contactSaveRejection(largeText: true, voiceOver: true)
    }
    private func contactSaveRejection(largeText: Bool, voiceOver: Bool = false, nativeRejection: Bool = false) throws {
        try restorePrelinkNavigation()
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_CONTACT_SAVE_REJECTION"] == "1", "Uses only the approved synthetic card; never submits an update to it.")
        XCTAssertEqual(environment["SIMULATOR_DEVICE_NAME"], "Legion Buddy Checks - iPhone 17 Pro")
        let identifier = try XCTUnwrap(environment["BUDDY_CHECKS_NATIVE_CONTACT_ID"])
        let app = launch(largeText: largeText, export: true, nativeContact: identifier, nativeCompanyReview: "before", rejectContactSave: !nativeRejection)
        if nativeRejection {
            app.terminate()
            app.launchEnvironment["BUDDY_CHECKS_CONNECTED_REJECT_CONTACT_SAVE"] = "native"
            app.launch()
            XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10))
        }
        let store = XCTAttachment(string: try XCTUnwrap(app.launchEnvironment["BUDDY_CHECKS_TEST_STORE"]))
        store.name = "Rejected save isolated store"; store.lifetime = .keepAlways; add(store)
        func reach(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 10))
            for _ in 0..<30 {
                let top = app.navigationBars.firstMatch.frame.maxY + 8
                if element.isHittable && element.frame.minY >= top && element.frame.maxY < (app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 16 : app.frame.maxY - 28) { break }
                let up = element.frame.minY >= top
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.77 : 0.34))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.43 : 0.68)))
            }
            XCTAssertTrue(element.isHittable)
        }
        func action(_ label: String) { if revealContactOption(label, app: app) { app.buttons[label].tap(); return }; let button = app.buttons[label]; reach(button); button.tap() }
        action("Suggest someone, From Post records"); action("Check on Alex")
        action("Phone contact")
        XCTAssertTrue(app.staticTexts["Post contact details"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Review Post updates"].exists, "Linked details open without another navigation step")
        XCTAssertFalse(app.buttons["Choose existing contact"].exists)
        XCTAssertFalse(app.buttons["Create new contact"].exists)
        XCTAssertFalse(app.switches["Use home label"].exists || app.buttons["Use home label"].exists)
        capture("Direct linked Contacts review", app: app)
        let company = app.switches.matching(identifier: "Use Post company").firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 10)); XCTAssertEqual(company.value as? String, "0")
        reach(company); company.tap(); XCTAssertEqual(company.value as? String, "1")
        let message = "The contact could not be saved. Your previous details have been kept. Try again."
        for attempt in 1...2 {
            if voiceOver, #available(iOS 27.0, *) {
                reach(app.buttons["Save changes"])
                let service = XCUIDevice.shared.voiceOverService
                addTeardownBlock { try await MainActor.run { try XCUIDevice.shared.voiceOverService.disable() } }
                try service.enable()
                var output = try service.currentSpeech().utterance
                for _ in 0..<36 where !output.contains("Save changes Button") { output = try service.moveForward().utterance }
                guard output.contains("Save changes Button") else {
                    try service.disable(); XCTFail("VoiceOver could not reach Save"); return
                }
                // VoiceOver activates the focused control with a double tap.
                app.buttons["Save changes"].doubleTap()
                let errorAppeared = app.alerts["Contacts"].waitForExistence(timeout: 10)
                // Rendering the label and delivering accessibility focus are
                // separate asynchronous events; observe the latter explicitly.
                let errorFocused = NSPredicate { _, _ in
                    guard let speech = try? service.currentSpeech().utterance else { return false }
                    return speech.hasPrefix("Contacts") || speech.hasPrefix("The contact could not be saved.")
                }
                let focusResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: errorFocused, object: nil)], timeout: 5)
                var errorSpeech = [try service.currentSpeech().utterance]
                for _ in 0..<8 where !errorSpeech.joined(separator: " ").contains("Return to review Button") {
                    errorSpeech.append(try service.moveForward().utterance)
                }
                let transcript = errorSpeech.joined(separator: "\n")
                let speech = XCTAttachment(string: output + "\n" + transcript)
                speech.name = "Rejected save VoiceOver attempt \(attempt)"; speech.lifetime = .keepAlways; add(speech)
                try service.disable()
                XCTAssertTrue(errorAppeared)
                XCTAssertEqual(focusResult, .completed, "Rejection must deliver accessibility focus")
                XCTAssertTrue(transcript.contains("The contact could not be saved."))
                XCTAssertTrue(transcript.contains("Return to review Button"))
            } else { action("Save changes") }
            let alert = app.alerts["Contacts"]
            XCTAssertTrue(alert.waitForExistence(timeout: 10))
            let error = alert.staticTexts[message]
            XCTAssertTrue(error.waitForExistence(timeout: 10))
            capture("Rejected contact save \(attempt) \(largeText ? "largest" : "ordinary")", app: app)
            if !voiceOver {
                let visible = NSPredicate { _, _ in
                    error.exists && error.frame.minY >= app.frame.minY + 48
                        && error.frame.maxY < app.frame.maxY - 28
                }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: nil)], timeout: 5), .completed,
                               "A failed Save must reveal its error without a search through the review")
            }
            alert.buttons["Return to review"].tap()
            XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Contact updated."].exists)
            XCTAssertEqual(company.value as? String, "1", "Rejected save must retain the explicit choice")
        }
        action("Cancel review"); openContactReview(app)
        XCTAssertTrue(company.waitForExistence(timeout: 10)); XCTAssertEqual(company.value as? String, "0")
        XCTAssertFalse(app.staticTexts[message].exists)
        action("Cancel review")
        app.terminate(); app.launchEnvironment["BUDDY_CHECKS_CONNECTED_NATIVE_COMPANY_REVIEW"] = "restored"
        app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10))
    }
    func testNativeCompanyUpdateAndRestoration() throws { try nativeCompanyUpdate(largeText: false) }
    func testNativeCompanyUpdateAndRestorationAtLargestText() throws { try nativeCompanyUpdate(largeText: true) }
    private func nativeCompanyUpdate(largeText: Bool) throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_NATIVE_CONTACT_UPDATE"] == "1", "Requires approval for updating and restoring the synthetic simulator card.")
        XCTAssertEqual(environment["SIMULATOR_DEVICE_NAME"], "Legion Buddy Checks - iPhone 17 Pro")
        let identifier = try XCTUnwrap(environment["BUDDY_CHECKS_NATIVE_CONTACT_ID"])
        let app = launch(largeText: largeText, export: true, nativeContact: identifier, nativeCompanyReview: "before")
        let testStore = XCTAttachment(string: try XCTUnwrap(app.launchEnvironment["BUDDY_CHECKS_TEST_STORE"]))
        testStore.name = "Native company review isolated store"; testStore.lifetime = .keepAlways; add(testStore)
        func reach(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 10))
            for _ in 0..<30 {
                let top = app.navigationBars.firstMatch.frame.maxY + 8
                if element.isHittable && element.frame.minY >= top && element.frame.maxY < (app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 16 : app.frame.maxY - 28) { break }
                let up = element.frame.minY >= top
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.77 : 0.34))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.43 : 0.68)))
            }
            XCTAssertTrue(element.isHittable)
        }
        func action(_ label: String) { if revealContactOption(label, app: app) { app.buttons[label].tap(); return }; let control = app.buttons[label]; reach(control); control.tap() }
        func openReview() {
            action("Suggest someone, From Post records"); action("Check on Alex")
            action("Phone contact"); openContactReview(app)
            XCTAssertTrue(app.staticTexts["Current: Robert"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Current: Miller"].exists)
            XCTAssertTrue(app.staticTexts["Current: robert.miller@example.org"].exists)
        }
        func saveOnlyCompany(current: String) {
            XCTAssertTrue(app.staticTexts["Current: \(current)"].exists)
            let labels = ["Use Post first name", "Use Post last name", "Use Post company", "Add Post email"]
            let controls = labels.map { app.switches.matching(identifier: $0).firstMatch }
            capture("Connected company conflicts \(largeText ? "largest" : "ordinary")", app: app)
            for control in controls { XCTAssertTrue(control.exists); XCTAssertEqual(control.value as? String, "0") }
            let company = controls[2]
            reach(company); company.tap()
            XCTAssertEqual(company.value as? String, "1")
            XCTAssertEqual(controls.filter { ($0.value as? String) == "1" }.count, 1)
            capture("Connected company selection \(largeText ? "largest" : "ordinary")", app: app)
            action("Save changes")
            XCTAssertTrue(app.staticTexts["Contact updated."].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Save changes"].exists)
            capture("Connected native company saved \(largeText ? "largest" : "ordinary")", app: app)
        }
        func relaunch(_ phase: String) {
            app.terminate()
            app.launchEnvironment["BUDDY_CHECKS_CONNECTED_NATIVE_COMPANY_REVIEW"] = phase
            app.launch()
            XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10))
        }
        openReview(); saveOnlyCompany(current: "American Legion Post 165")
        // The fixture reads the actual Contacts store after each process restart.
        relaunch("updated")
        openReview(); saveOnlyCompany(current: "Synthetic Contacts Update Test")
        relaunch("restored")
        openReview()
        XCTAssertFalse(app.switches["Use Post company"].exists)
        for label in ["Use Post first name", "Use Post last name", "Add Post email"] {
            let control = app.switches.matching(identifier: label).firstMatch
            XCTAssertTrue(control.exists); XCTAssertEqual(control.value as? String, "0")
        }
        capture("Connected native company restored \(largeText ? "largest" : "ordinary")", app: app)
        action("Cancel review")
    }
    func testNativeLimitedContactsReviewInvalidationAndRestoration() throws { try nativeLimitedContacts(largeText: false) }
    func testNativeLimitedContactsReviewInvalidationAtLargestText() throws { try nativeLimitedContacts(largeText: true) }
    private func nativeLimitedContacts(largeText: Bool) throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["BUDDY_CHECKS_NATIVE_CONTACTS"] == "1", "Requires explicit permission to temporarily unshare and restore the synthetic simulator contact.")
        XCTAssertEqual(environment["SIMULATOR_DEVICE_NAME"], "Legion Buddy Checks - iPhone 17 Pro")
        let identifier = try XCTUnwrap(environment["BUDDY_CHECKS_NATIVE_CONTACT_ID"])
        let app = launch(largeText: largeText, export: true, nativeContact: identifier)
        func action(_ label: String) {
            if revealContactOption(label, app: app) { app.buttons[label].tap(); return }
        let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            for _ in 0..<24 {
                let top = app.navigationBars.firstMatch.frame.maxY + 8
                if button.isHittable && button.frame.minY >= top && button.frame.maxY < (app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 16 : app.frame.maxY - 28) { break }
                let up = button.frame.minY >= top
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.77 : 0.34))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.43 : 0.68)))
            }
            XCTAssertTrue(button.isHittable); button.tap()
        }
        func shareRobert(_ shared: Bool) {
            action("Choose contacts shared with this app")
            let search = app.searchFields["Search"]
            XCTAssertTrue(search.waitForExistence(timeout: 20))
            let row: XCUIElement
            let selectedSheet = app.buttons["Show Selected (1)"].exists
            if selectedSheet {
                // Filtering the one shared card avoids offscreen native rows at maximum text.
                app.buttons["Show Selected (1)"].tap()
                row = app.cells["Robert Miller, American Legion Post 165"]
            } else {
                search.tap(); search.typeText("Robert Miller")
                let results = app.collectionViews["Search results"]
                let result = results.cells["Robert Miller, American Legion Post 165"]
                XCTAssertTrue(result.waitForExistence(timeout: 10)); result.tap()
                // Choosing a search result closes search and reveals its selected full-list row.
                XCTAssertTrue(results.waitForNonExistence(timeout: 5))
                row = app.cells["Robert Miller, American Legion Post 165"]
            }
            XCTAssertTrue(row.waitForExistence(timeout: 10)); XCTAssertTrue(row.isHittable)
            if row.isSelected != shared { row.tap() }
            let selection = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == %@", NSNumber(value: shared)), object: row)
            XCTAssertEqual(XCTWaiter.wait(for: [selection], timeout: 5), .completed)
            capture("Native selection \(shared ? "restored" : "removed") \(largeText ? "largest" : "ordinary")", app: app)
            if selectedSheet {
                // This is a nested selection sheet. Its Done is disabled without changes.
                if app.buttons["Done"].isEnabled { app.buttons["Done"].tap() }
                else { app.buttons["Cancel"].tap() }
                XCTAssertTrue(search.waitForExistence(timeout: 10))
            }
            app.buttons["Done"].tap()
            XCTAssertTrue(search.waitForNonExistence(timeout: 10))
        }
        action("Suggest someone, From Post records")
        action("Check on Alex"); action("Phone contact")
        shareRobert(true)
        XCTAssertTrue(app.staticTexts["Post contact details"].waitForExistence(timeout: 10) || app.buttons["Review Post updates"].exists)
        openContactReview(app)
        XCTAssertTrue(app.staticTexts["Current: Robert"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Current: Miller"].exists)
        XCTAssertTrue(app.staticTexts["Current: robert.miller@example.org"].exists)
        // An unchanged native selection must preserve the review.
        shareRobert(true)
        XCTAssertTrue(app.staticTexts["Current: Robert"].waitForExistence(timeout: 10))
        // Backgrounding locks the connected account and discards navigation.
        // Returning to this contact must read it again through its saved link.
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Synthetic Post"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Current: Robert"].exists)
        action("Suggest someone, From Post records")
        action("Check on Alex"); action("Phone contact"); openContactReview(app)
        XCTAssertTrue(app.staticTexts["Current: Robert"].waitForExistence(timeout: 10))
        shareRobert(false)
        let unavailable = app.staticTexts["The linked contact is unavailable. It may have been deleted or is no longer shared with this app."]
        let cleared = unavailable.waitForExistence(timeout: 8)
            && !app.staticTexts["Current: Robert"].exists
            && !app.staticTexts["Current: Miller"].exists
            && !app.staticTexts["Current: robert.miller@example.org"].exists
            && !app.buttons["Use this contact"].exists
            && !app.buttons["Save changes"].exists
            && !app.buttons["Review Post updates"].exists
        capture("Unshared contact clears review \(largeText ? "largest" : "ordinary")", app: app)
        var speech: String?
        var speechError: Error?
        if largeText, #available(iOS 27.0, *) {
            let service = XCUIDevice.shared.voiceOverService; let wasEnabled = service.isEnabled
            defer { if !wasEnabled { try? service.disable() } }
            do {
                try service.enable()
                var labels = [try service.currentSpeech().utterance]
                for _ in 0..<25 {
                    let next = try service.moveForward().utterance
                    if next == labels.last { break }; labels.append(next)
                    if next.contains("Choose contacts shared with this app") { break }
                }
                speech = labels.joined(separator: "\n")
                let attachment = XCTAttachment(string: speech!)
                attachment.name = "Native unshared Contacts VoiceOver"; attachment.lifetime = .keepAlways; add(attachment)
            } catch {
                // Restore sharing before surfacing a speech-service failure.
                speechError = error
            }
        }
        // Restore the approved selection before reporting the regression assertion.
        shareRobert(true)
        if let speechError { throw speechError }
        XCTAssertTrue(cleared, "An unshared contact must lose its personal fields and review actions")
        if let speech {
            XCTAssertTrue(speech.contains("linked contact is unavailable") && speech.contains("Choose contacts shared with this app"))
            XCTAssertFalse(speech.contains("Robert") || speech.contains("Miller") || speech.contains("Save changes"))
        }
        XCTAssertTrue(app.buttons["Review Post updates"].waitForExistence(timeout: 10), "The retained association should work again without choosing or creating a contact")
        XCTAssertFalse(app.staticTexts["This contact is unavailable. It may have been deleted or is no longer shared with this app."].exists)
        capture("Native contact link available again \(largeText ? "largest" : "ordinary")", app: app)
        openContactReview(app)
        XCTAssertTrue(app.staticTexts["Current: Robert"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Current: Miller"].exists)
        XCTAssertTrue(app.staticTexts["Current: robert.miller@example.org"].exists)
        capture("Existing native contact review restored \(largeText ? "largest" : "ordinary")", app: app)
        action("Cancel review")
    }

    func testMemberRefreshRechecksAuthorityAndRecoversWithoutRecording() throws { try memberRefresh(largeText: false) }
    func testMemberRefreshAtLargestTextWithVoiceOver() throws { try memberRefresh(largeText: true) }
    private func memberRefresh(largeText: Bool) throws {
        let app = launch(largeText: largeText, export: true, changedMember: true)
        func action(_ label: String) {
            if revealContactOption(label, app: app) { app.buttons[label].tap(); return }
        let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            for _ in 0..<24 {
                let top = app.navigationBars.firstMatch.frame.maxY + 8
                if button.isHittable && button.frame.minY >= top && button.frame.maxY < (app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 16 : app.frame.maxY - 28) { break }
                let up = button.frame.minY >= top
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.77 : 0.34))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.43 : 0.68)))
            }
            XCTAssertTrue(button.isHittable); button.tap()
        }
        action("Suggest someone, From Post records"); action("Check on Alex")
        XCTAssertTrue(app.staticTexts["Alex Example"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["A way to start"].exists)
        XCTAssertTrue(app.buttons["Record a check"].isEnabled && app.buttons["Phone contact"].exists)
        action("Refresh member")
        XCTAssertTrue(app.staticTexts["Contact with this member is paused."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["A way to start"].exists)
        XCTAssertFalse(app.buttons["Record a check"].isEnabled)
        XCTAssertTrue(app.buttons["Phone contact"].exists, "Contacts export authority is separate from outreach eligibility")
        capture("Refreshed member pause \(largeText ? "largest" : "ordinary")", app: app)
        for (index, message) in [
            "This member is unavailable from the Post.",
            "The Post could not be reached. Refresh to check current member access.",
            "These member details could not be verified. Refresh to try again."
        ].enumerated() {
            action("Refresh member")
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Alex Example"].exists || app.staticTexts["Avery Example"].exists)
            XCTAssertFalse(app.staticTexts["A way to start"].exists || app.staticTexts["Contact with this member is paused."].exists)
            XCTAssertFalse(app.buttons["Record a check"].exists || app.buttons["Phone contact"].exists)
            capture("Unavailable member \(index) \(largeText ? "largest" : "ordinary")", app: app)
            if largeText && index == 0, #available(iOS 27.0, *) {
                let service = XCUIDevice.shared.voiceOverService; let wasEnabled = service.isEnabled
                try service.enable()
                defer { if !wasEnabled { try? service.disable() } }
                var speech = [try service.currentSpeech().utterance]
                for _ in 0..<14 {
                    let next = try service.moveForward().utterance
                    if next == speech.last { break }; speech.append(next)
                }
                let transcript = speech.joined(separator: "\n")
                let attachment = XCTAttachment(string: transcript)
                attachment.name = "Unavailable member VoiceOver"; attachment.lifetime = .keepAlways; add(attachment)
                XCTAssertTrue(transcript.contains("unavailable from the Post") && transcript.contains("Refresh member"))
                XCTAssertFalse(transcript.contains("Alex Example") || transcript.contains("Record a check"))
            }
        }
        action("Refresh member")
        XCTAssertTrue(app.staticTexts["Avery Example"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Alex Example"].exists)
        XCTAssertTrue(app.staticTexts["A way to start"].exists)
        XCTAssertTrue(app.buttons["Record a check"].isEnabled && app.buttons["Phone contact"].exists)
        capture("Member access recovered \(largeText ? "largest" : "ordinary")", app: app)
        for _ in 0..<2 { app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.buttons["Your checks"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue unfinished check"].exists || app.buttons["Check submission"].exists)
        action("Your checks")
        XCTAssertTrue(app.staticTexts["You haven't recorded a Buddy Check here yet."].waitForExistence(timeout: 5))
    }
    func testFreshFollowUpDetailClearsStaleActionsAndRecovers() throws { try freshFollowUp(largeText: false) }
    func testFreshFollowUpDetailAtLargestText() throws { try freshFollowUp(largeText: true) }
    func testCurrentFollowUpVoiceOver() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Requires the native VoiceOver test service.") }
        let app = launch(largeText: true, changedFollowUp: true)
        app.tabBars.buttons["Follow-ups"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex Example,")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))
        let voiceOver = XCUIDevice.shared.voiceOverService
        let wasEnabled = voiceOver.isEnabled
        try voiceOver.enable()
        defer { if !wasEnabled { try? voiceOver.disable() } }
        var labels: [String] = []
        for _ in 0..<18 {
            labels.append(try voiceOver.currentSpeech().utterance)
            _ = try voiceOver.moveForward()
        }
        let transcript = labels.joined(separator: "\n")
        let attachment = XCTAttachment(string: transcript)
        attachment.name = "Current follow-up VoiceOver"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(transcript.contains("Alex Example") && transcript.contains("Completed") && transcript.contains("Refresh follow-up"))
        XCTAssertFalse(transcript.contains("Mark follow-up complete") || transcript.contains("Reschedule"))
    }

    private func freshFollowUp(largeText: Bool) throws {
        let app = launch(largeText: largeText, changedFollowUp: true)
        app.tabBars.buttons["Follow-ups"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Alex Example,", "Open")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Mark follow-up complete"].exists)
        XCTAssertFalse(app.buttons["Reschedule"].exists)
        XCTAssertFalse(app.buttons["Cancel follow-up"].exists)
        capture(largeText ? "Current closed follow-up at largest text" : "Current closed follow-up replaces open list row", app: app)
        tap("Refresh follow-up", app: app)
        XCTAssertTrue(app.staticTexts["The Post could not be reached. Refresh this follow-up to try again."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Completed"].exists)
        XCTAssertFalse(app.staticTexts["Alex Example"].exists)
        XCTAssertFalse(app.buttons["Mark follow-up complete"].exists)
        capture(largeText ? "Failed follow-up refresh at largest text" : "Failed follow-up refresh clears stale facts", app: app)
        tap("Refresh follow-up", app: app)
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Alex Example"].exists)
        for _ in 0..<2 { app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap() }
        XCTAssertFalse(app.buttons["Continue unfinished check"].exists)
        XCTAssertFalse(app.buttons["Check submission"].exists)
        tap("Your checks", app: app)
        XCTAssertTrue(app.staticTexts["You haven't recorded a Buddy Check here yet."].waitForExistence(timeout: 5))
    }

    private func openContactReview(_ app: XCUIApplication) {
        if app.buttons["Review Post updates"].exists {
            tap("Review Post updates", app: app) // Explicit recovery after cancellation or stale data.
        }
        XCTAssertTrue(app.staticTexts["Post contact details"].waitForExistence(timeout: 10))
    }
    private func revealContactOption(_ label: String, app: XCUIApplication) -> Bool {
        let options = ["Cancel review", "Create new contact", "Choose existing contact", "Refresh Post details"]
        if options.contains(label), !app.buttons[label].exists, app.buttons["Contact options"].exists {
            app.buttons["Contact options"].tap()
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5))
            return true
        }
        return false
    }
    private func tap(_ label: String, app: XCUIApplication) {
        if revealContactOption(label, app: app) { app.buttons[label].tap(); return }
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing \(label)")
        // A partially exposed button can report hittable while its tap point
        // lies under the floating tab bar. Scroll that point into the page.
        for _ in 0..<16 {
            let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 12 : app.frame.maxY - 28
            if button.isHittable && button.frame.midY < bottom { break }
            scrollPage(app)
        }
        if !button.isHittable { capture("Unreachable " + label, app: app) }
        XCTAssertTrue(button.isHittable, "Unreachable \(label)")
        button.tap()
    }
    private func scrollPage(_ app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        let bottom = keyboard.exists ? min(app.frame.height * 0.8, keyboard.frame.minY - 20) : app.frame.height * 0.8
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.97, dy: bottom))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + " accessibility tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func testStaleCorrectionReviewFromHomePreservesNotes() throws {
        try staleCorrectionReview(largeText: false, fromHome: true)
    }
    func testStaleCorrectionReviewLargestText() throws {
        try staleCorrectionReview(largeText: true, fromHome: false)
    }
    func testStaleCorrectionComparisonVoiceOver() throws {
        try staleCorrectionReview(largeText: true, fromHome: false, voiceOverOnly: true)
    }
    private func staleCorrectionReview(largeText: Bool, fromHome: Bool, voiceOverOnly: Bool = false) throws {
        let app = launch(largeText: largeText, staleCorrection: true)
        tap("Your checks", app: app)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex Example, No answer")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        tap("Correct this check", app: app)
        tap("We connected", app: app)
        let notes = app.textFields.firstMatch
        for _ in 0..<8 where !notes.isHittable { app.swipeUp() }
        notes.tap()
        // Keep the existing notes while adding this proposed fact.
        notes.typeText(" Caller correction retained.")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        tap("Save correction", app: app)
        XCTAssertTrue(app.staticTexts["This check changed at the Post"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["The Post confirmed your Buddy Check."].exists)
        if fromHome {
            for _ in 0..<3 { app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap() }
            XCTAssertTrue(app.staticTexts["Submission not saved"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Check on someone, Search the Post member list"].exists)
        }
        tap("Review latest check", app: app)
        XCTAssertTrue(app.staticTexts["Current Post record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Updated in another session."].exists)
        XCTAssertTrue(app.staticTexts["Your proposed correction"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Caller correction retained.")).firstMatch.exists)
        capture(largeText ? "Stale correction comparison largest text top" : "Stale correction comparison", app: app)
        if voiceOverOnly, #available(iOS 27.0, *) {
            let voiceOver = XCUIDevice.shared.voiceOverService
            let wasEnabled = voiceOver.isEnabled
            try voiceOver.enable()
            defer { if !wasEnabled { try? voiceOver.disable() } }
            var labels: [String] = []
            for _ in 0..<40 {
                let label = try voiceOver.currentSpeech().utterance
                labels.append(label)
                _ = try voiceOver.moveForward()
            }
            let transcript = labels.joined(separator: "\n")
            let attachment = XCTAttachment(string: transcript); attachment.name = "Stale correction VoiceOver"; attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertTrue(transcript.contains("Current Post record") && transcript.contains("Your proposed correction"))
            XCTAssertTrue(transcript.contains("Continue with my correction"))
            return
        }
        // Back leaves the rejected operation intact; review it again before choosing.
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        tap("Review latest check", app: app)
        let continueButton = app.buttons["Continue with my correction"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        for _ in 0..<16 where !continueButton.isHittable { scrollPage(app) }
        scrollPage(app)
        capture(largeText ? "Stale correction comparison largest text action" : "Stale correction explicit continue", app: app)
        continueButton.tap()
        XCTAssertTrue(app.buttons["Save correction"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Review latest check"].exists)
        XCTAssertFalse(app.staticTexts["The Post confirmed your Buddy Check."].exists)
        XCTAssertTrue((app.textFields.firstMatch.value as? String)?.contains("Caller correction retained.") == true)
        tap("Save correction", app: app)
        XCTAssertTrue(app.staticTexts["The Post confirmed your Buddy Check."].waitForExistence(timeout: 5))
        capture("Reviewed correction accepted", app: app)
    }
    func testConnectedSuggestionRecordAndServerReceipt() {
        let app = launch()
        capture("Connected Post home", app: app)
        tap("Suggest someone, From Post records", app: app)
        XCTAssertTrue(app.staticTexts["Alex Example"].waitForExistence(timeout: 5))
        capture("Connected server suggestion", app: app)
        tap("Check on Alex", app: app)
        tap("Record a check", app: app)
        tap("No answer", app: app)
        let followUp = app.switches["Set a follow-up"]
        for _ in 0..<6 where !followUp.isHittable { app.swipeUp() }
        followUp.tap()
        capture("Connected check form", app: app)
        tap("Save to Post", app: app)
        XCTAssertTrue(app.staticTexts["The Post confirmed your Buddy Check."].waitForExistence(timeout: 5))
        capture("Connected receipt accepted", app: app)
        tap("Back to Home", app: app)
        tap("Your checks", app: app)
        let record = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex Example, No answer")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap()
        tap("Correct this check", app: app)
        tap("We connected", app: app)
        tap("Save correction", app: app)
        XCTAssertTrue(app.staticTexts["The Post confirmed your Buddy Check."].waitForExistence(timeout: 5))
        capture("Connected correction accepted", app: app)
        tap("Back to Home", app: app)
        app.tabBars.buttons["Follow-ups"].tap()
        let callback = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex Example,")).firstMatch
        XCTAssertTrue(callback.waitForExistence(timeout: 5)); callback.tap()
        tap("Mark follow-up complete", app: app)
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))
        capture("Connected follow-up completed", app: app)
    }
    func testConnectedLostResponseAndLargestText() {
        let app = launch(largeText: true, lostResponse: true)
        tap("Suggest someone, From Post records", app: app)
        capture("Connected suggestion largest text", app: app)
        tap("Check on Alex", app: app)
        tap("Record a check", app: app)
        tap("I left a message", app: app)
        tap("Save to Post", app: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Submission pending.")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["The Post confirmed your Buddy Check."].exists)
        capture("Connected uncertain submission largest text", app: app)
        // Pop form, member and suggestion back to connected home.
        for _ in 0..<3 { app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap() }
        tap("Check submission", app: app)
        XCTAssertTrue(app.staticTexts["Saved to the Post"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Check submission"].exists)
        capture("Connected recovered receipt largest text", app: app)
    }
    func testConnectedContactRefreshClearsUnavailableFieldsAndRetainsLink() throws {
        try contactRefreshRecovery(largeText: false)
    }
    func testConnectedContactRefreshRecoveryAtLargestTextWithVoiceOver() throws {
        try contactRefreshRecovery(largeText: true)
    }
    private func contactRefreshRecovery(largeText: Bool) throws {
        let app = launch(largeText: largeText, export: true, changedExport: true)
        func action(_ label: String) {
            if revealContactOption(label, app: app) { app.buttons[label].tap(); return }
        let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            for _ in 0..<24 {
                let top = app.navigationBars.firstMatch.frame.maxY + 8
                if button.isHittable && button.frame.minY >= top && button.frame.maxY < (app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 16 : app.frame.maxY - 28) { break }
                let up = button.frame.minY >= top
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.77 : 0.34))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.43 : 0.68)))
            }
            XCTAssertTrue(button.isHittable); button.tap()
        }
        action("Suggest someone, From Post records"); action("Check on Alex"); action("Phone contact")
        XCTAssertTrue(app.staticTexts["first@example.test"].waitForExistence(timeout: 10))
        let pending = "A contact may already have been saved. Choose it below to finish linking."
        let unavailableLink = "The linked contact is unavailable. It may have been deleted or is no longer shared with this app."
        XCTAssertTrue(app.staticTexts[pending].exists && app.staticTexts[unavailableLink].exists)
        for (index, message) in [
            "The Post does not permit this Contacts copy.",
            "These Post details could not be verified. Retry before copying them.",
            "The Post could not be reached. Retry to load current contact details."
        ].enumerated() {
            action("Refresh Post details")
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Alex Example"].exists)
            XCTAssertFalse(app.staticTexts["American Legion Post 165"].exists)
            XCTAssertFalse(app.staticTexts["first@example.test"].exists || app.staticTexts["current@example.test"].exists)
            XCTAssertFalse(app.buttons["Create new contact"].exists || app.buttons["Choose existing contact"].exists)
            capture("Connected Contacts unavailable \(index) \(largeText ? "largest" : "ordinary")", app: app)
            if largeText && index == 0, #available(iOS 27.0, *) {
                let service = XCUIDevice.shared.voiceOverService; let wasEnabled = service.isEnabled
                try service.enable()
                defer { if !wasEnabled { try? service.disable() } }
                var speech = [try service.currentSpeech().utterance]
                for _ in 0..<16 {
                    let next = try service.moveForward().utterance
                    if next == speech.last { break }; speech.append(next)
                }
                let transcript = speech.joined(separator: "\n")
                let attachment = XCTAttachment(string: transcript); attachment.name = "Connected Contacts recovery VoiceOver"; attachment.lifetime = .keepAlways; add(attachment)
                XCTAssertTrue(transcript.contains("Retry Post details"))
                XCTAssertTrue(transcript.contains("does not permit this Contacts copy"))
                XCTAssertFalse(transcript.contains("Alex Example") || transcript.contains("@example.test"))
            }
            action("Retry Post details")
            XCTAssertTrue(app.staticTexts["current@example.test"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["first@example.test"].exists)
            XCTAssertTrue(app.staticTexts[pending].exists && app.staticTexts[unavailableLink].exists)
        }
        capture("Connected Contacts recovered current fields \(largeText ? "largest" : "ordinary")", app: app)
        for _ in 0..<3 { app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.buttons["Your checks"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue unfinished check"].exists || app.buttons["Check submission"].exists)
        action("Your checks")
        XCTAssertTrue(app.staticTexts["You haven't recorded a Buddy Check here yet."].waitForExistence(timeout: 5))
    }

    func testConnectedPermittedContactsAndVoiceOver() throws {
        let app = launch(export: true)
        tap("Suggest someone, From Post records", app: app)
        tap("Check on Alex", app: app)
        tap("Phone contact", app: app)
        XCTAssertTrue(app.staticTexts["American Legion Post 165"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["alex@example.test"].exists)
        XCTAssertTrue(app.buttons["Create new contact"].exists)
        XCTAssertTrue(app.buttons["Choose existing contact"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "12 Example Way")).firstMatch.exists)
        capture("Connected permitted Contacts", app: app)
        if #available(iOS 27.0, *) {
            let service = XCUIDevice.shared.voiceOverService
            let wasEnabled = service.isEnabled
            defer { if !wasEnabled { try? service.disable() } }
            try service.enable()
            var speech = [try service.currentSpeech().utterance]
            for _ in 0..<24 {
                let next = try service.moveForward().utterance
                if speech.last == next { break }
                speech.append(next)
            }
            let attachment = XCTAttachment(string: speech.joined(separator: "\n")); attachment.name = "Connected Contacts VoiceOver"; attachment.lifetime = .keepAlways; add(attachment)
            let transcript = speech.joined(separator: " ").lowercased()
            for text in ["alex example", "american legion post 165", "choose existing contact", "create new contact"] {
                XCTAssertTrue(transcript.contains(text), "Missing spoken control: \(text)")
            }
        }
    }
    func testRandomSuggestionsAreBrowsing() { checkRandomSuggestions(largeText: false) }
    func testRandomSuggestionsAtLargestText() { checkRandomSuggestions(largeText: true) }
    private func checkRandomSuggestions(largeText: Bool) {
        let app = launch(largeText: largeText, randomSuggestions: true)
        tap("Suggest someone, From Post records", app: app)
        XCTAssertTrue(app.staticTexts["More history is needed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Picked at random from eligible members."].exists)
        for name in ["Alex Example", "Taylor Example", "Morgan Example"] {
            XCTAssertTrue(app.buttons["Check on \(name)"].exists)
        }
        capture("Random choices below unknown history \(largeText ? "large" : "ordinary")", app: app)
        tap("Check on Alex Example", app: app)
        XCTAssertTrue(app.buttons["Record a check"].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.buttons["Continue unfinished check"].exists)
        XCTAssertFalse(app.buttons["Check submission"].exists)
        tap("Your checks", app: app)
        XCTAssertTrue(app.staticTexts["You haven't recorded a Buddy Check here yet."].waitForExistence(timeout: 5))
    }
    func testConnectedSuggestionsAreBrowsing() {
        let app = launch()
        tap("Suggest someone, From Post records", app: app)
        XCTAssertTrue(app.buttons["Check on Alex"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Snooze for a week"].exists)
        XCTAssertFalse(app.buttons["Skip for 7 days"].exists)
        tap("Someone else", app: app)
        XCTAssertTrue(app.staticTexts["More history is needed"].waitForExistence(timeout: 5))
        tap("Refresh suggestion", app: app)
        XCTAssertTrue(app.staticTexts["More history is needed"].waitForExistence(timeout: 5))
        tap("Include skipped members again", app: app)
        XCTAssertTrue(app.buttons["Check on Alex"].waitForExistence(timeout: 5))
        capture("Connected suggestion browsing", app: app)
        tap("Check on Alex", app: app)
        XCTAssertTrue(app.buttons["Record a check"].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.buttons["Continue unfinished check"].exists)
        XCTAssertFalse(app.buttons["Check submission"].exists)
        tap("Your checks", app: app)
        XCTAssertTrue(app.staticTexts["You haven't recorded a Buddy Check here yet."].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Follow-ups"].tap()
        XCTAssertTrue(app.staticTexts["You have no recorded follow-ups."].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        tap("Hidden suggestions", app: app)
        XCTAssertTrue(app.staticTexts["You have no hidden suggestions."].waitForExistence(timeout: 5))
    }

    func testConnectedPauseDoesNotInviteContactLargestText() throws {
        let app = launch(largeText: true, paused: true)
        tap("Suggest someone, From Post records", app: app)
        tap("Check on Alex", app: app)
        XCTAssertTrue(app.staticTexts["Contact with this member is paused."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["A way to start"].exists)
        XCTAssertFalse(app.buttons["Record a check"].isEnabled)
        capture("Connected paused contact largest text", app: app)
        if #available(iOS 27.0, *) {
            let service = XCUIDevice.shared.voiceOverService
            let wasEnabled = service.isEnabled
            defer { if !wasEnabled { try? service.disable() } }
            try service.enable()
            var speech = [try service.currentSpeech().utterance]
            for _ in 0..<24 {
                let next = try service.moveForward().utterance
                if speech.last == next { break }
                speech.append(next)
            }
            let transcript = speech.joined(separator: " ").lowercased()
            XCTAssertTrue(transcript.contains("alex example"))
            XCTAssertTrue(transcript.contains("contact with this member is paused"))
            XCTAssertFalse(transcript.contains("a way to start"))
            let attachment = XCTAttachment(string: speech.joined(separator: "\n"))
            attachment.name = "Connected paused contact VoiceOver"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}

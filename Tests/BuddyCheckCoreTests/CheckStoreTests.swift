import Foundation
import Testing
@testable import BuddyCheckCore

@MainActor private final class MemoryPersistence: SnapshotPersistence {
    var value: LocalSnapshot?
    var failWrites = false
    func load() throws -> LocalSnapshot? { value }
    func save(_ snapshot: LocalSnapshot) throws {
        if failWrites { throw CocoaError(.fileWriteOutOfSpace) }
        value = snapshot
    }
}

@Suite @MainActor struct CheckStoreTests {
    let instant = Date(timeIntervalSince1970: 1_800_000_000)
    let robert = SyntheticDirectory.people[0].id
    let elena = SyntheticDirectory.people[1].id
    let zone = "America/Chicago"

    func disk() -> (JSONSnapshotPersistence, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (JSONSnapshotPersistence(fileURL: folder.appendingPathComponent("checks.json")), folder)
    }
    private func memory() -> (CheckStore, MemoryPersistence) {
        let persistence = MemoryPersistence()
        return (CheckStore(persistence: persistence, now: { instant }), persistence)
    }
    func ready(_ store: CheckStore, reminder: Bool = false) throws -> UUID {
        let id = try store.begin(personID: robert, origin: .manual, timeZone: zone)
        try store.updateDraft(id: id) { $0.occurredAt = instant.addingTimeInterval(-3600); $0.outcome = .connected }
        if reminder { try store.chooseReminder(id: id, timeZone: zone) }
        return id
    }

    @Test func restoresEveryDraftFieldFromDisk() throws {
        let (persistence, folder) = disk()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CheckStore(persistence: persistence, now: { instant })
        let id = try ready(store, reminder: true)
        try store.setMethod(id: id, method: .text)
        let reopened = CheckStore(persistence: JSONSnapshotPersistence(fileURL: persistence.fileURL), now: { instant })
        #expect(reopened.loadError == nil)
        #expect(reopened.draft == store.draft)
        #expect(reopened.draft?.stage == .reminder)
        #expect(reopened.draft?.method == .text)
        #expect(reopened.draft?.eventTimeZone == zone)
        #expect(reopened.draft?.occurredAt != reopened.draft?.startedAt)
    }

    @Test func blocksSecondDraftUntilExplicitDiscard() throws {
        let (store, _) = memory()
        let id = try ready(store)
        let before = store.draft
        #expect(throws: WorkflowError.unfinishedCheck) { try store.begin(personID: elena, origin: .simulatedCall, timeZone: zone) }
        #expect(store.draft == before)
        #expect(throws: WorkflowError.missingDraft) { try store.discardDraft(id: UUID()) }
        try store.discardDraft(id: id)
        try store.begin(personID: elena, origin: .simulatedCall, timeZone: zone)
        #expect(store.draft?.personID == elena)
        #expect(store.draft?.outcome == nil)
        #expect(store.checks.isEmpty)
    }

    @Test func repeatedSaveAfterRestartDoesNotDuplicateCheckOrFollowUp() throws {
        let (persistence, folder) = disk()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CheckStore(persistence: persistence, now: { instant })
        let id = try ready(store, reminder: true)
        let first = try store.saveDraft(id: id, includeFollowUp: true)
        #expect(try store.saveDraft(id: id, includeFollowUp: true) == first)
        let reopened = CheckStore(persistence: persistence, now: { instant.addingTimeInterval(600) })
        #expect(try reopened.saveDraft(id: id, includeFollowUp: true) == first)
        #expect(reopened.checks.count == 1)
        #expect(reopened.followUps.count == 1)
        #expect(reopened.draft == nil)
        #expect(first.recordedAt == instant)
        #expect(first.occurredAt == instant.addingTimeInterval(-3600))
    }

    @Test func correctionPreservesIdentityEntryTimeHistoryAndFollowUp() throws {
        let (store, persistence) = memory()
        let id = try ready(store, reminder: true)
        let original = try store.saveDraft(id: id, includeFollowUp: true)
        let followUp = store.followUps.first
        let later = CheckStore(persistence: persistence, now: { instant.addingTimeInterval(600) })
        try later.beginCorrection(checkID: id)
        try later.updateDraft(id: id) { $0.outcome = .noAnswer; $0.occurredAt = instant.addingTimeInterval(-7200) }
        let corrected = try later.saveDraft(id: id, includeFollowUp: false)
        #expect(later.checks.count == 1)
        #expect(corrected.id == original.id)
        #expect(corrected.recordedAt == original.recordedAt)
        #expect(corrected.updatedAt > original.updatedAt)
        #expect(corrected.revisions.count == 1)
        #expect(corrected.revisions.first?.previousOutcome == .connected)
        #expect(corrected.revisions.first?.previousOccurredAt == original.occurredAt)
        #expect(later.followUps.first == followUp)
        try later.beginCorrection(checkID: id)
        #expect(try later.saveDraft(id: id, includeFollowUp: false).revisions.count == 1)
    }

    @Test func simulatedCallDoesNotAssumeConversationOrSaveAnything() throws {
        let (store, _) = memory()
        let id = try store.begin(personID: robert, origin: .simulatedCall, timeZone: zone)
        #expect(store.draft?.stage == .outcome)
        #expect(store.draft?.outcome == nil)
        #expect(store.checks.isEmpty)
        #expect(throws: WorkflowError.missingOutcome) { try store.saveDraft(id: id, includeFollowUp: false) }
        try store.updateDraft(id: id) { $0.outcome = .notAttempted }
        let check = try store.saveDraft(id: id, includeFollowUp: false)
        #expect(!check.outcome.countsAsAttempt)
    }

    @Test func rejectsFutureEventPastReminderAndInvalidOutcome() throws {
        let (store, _) = memory()
        let id = try ready(store)
        try store.updateDraft(id: id) { $0.occurredAt = instant.addingTimeInterval(1) }
        #expect(throws: WorkflowError.futureEvent) { try store.finishDetails(id: id) }
        #expect(throws: WorkflowError.futureEvent) { try store.saveDraft(id: id, includeFollowUp: false) }
        try store.updateDraft(id: id) { $0.occurredAt = instant; $0.followUpDue = instant }
        #expect(throws: WorkflowError.pastReminder) { try store.saveDraft(id: id, includeFollowUp: true) }
        try store.updateDraft(id: id) { $0.method = .visit; $0.outcome = .wrongNumber }
        #expect(throws: WorkflowError.invalidOutcome) { try store.saveDraft(id: id, includeFollowUp: false) }
        #expect(store.checks.isEmpty)
        #expect(store.draft?.id == id)
    }

    @Test func changingMethodClearsIncompatibleOutcome() throws {
        let (store, _) = memory()
        let id = try ready(store)
        try store.updateDraft(id: id) { $0.outcome = .wrongNumber }
        try store.setMethod(id: id, method: .visit)
        #expect(store.draft?.outcome == nil)
    }

    @Test func failedWriteKeepsPreviousStateAndAllowsRetry() throws {
        let (store, persistence) = memory()
        let id = try ready(store, reminder: true)
        let before = store.snapshot
        persistence.failWrites = true
        #expect(throws: CocoaError.self) { try store.saveDraft(id: id, includeFollowUp: true) }
        #expect(store.snapshot == before)
        #expect(persistence.value == before)
        #expect(throws: CocoaError.self) { try store.updateDraft(id: id) { $0.outcome = .noAnswer } }
        #expect(store.snapshot == before)
        persistence.failWrites = false
        try store.saveDraft(id: id, includeFollowUp: true)
        #expect(store.checks.count == 1)
        #expect(store.followUps.count == 1)
    }

    @Test(arguments: ["not json", "{\"formatVersion\":99}"])
    func damagedOrNewerStorageIsPreservedAndBlocksWrites(contents: String) throws {
        let (persistence, folder) = disk()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = Data(contents.utf8)
        try original.write(to: persistence.fileURL)
        let store = CheckStore(persistence: persistence, now: { instant })
        #expect(store.loadError != nil)
        #expect(throws: WorkflowError.storageNotReady) { try store.begin(personID: robert, origin: .manual, timeZone: zone) }
        #expect(try Data(contentsOf: persistence.fileURL) == original)
        store.reload()
        #expect(store.loadError != nil)
    }

    @Test func closingFollowUpDoesNotCreateCheckAndCannotBeRescheduled() throws {
        let (store, _) = memory()
        let id = try ready(store, reminder: true)
        try store.saveDraft(id: id, includeFollowUp: true)
        let followUpID = try #require(store.followUps.first?.id)
        let due = instant.addingTimeInterval(7200)
        try store.rescheduleFollowUp(id: followUpID, due: due, timeZone: "America/Los_Angeles")
        #expect(store.followUps.first?.due == due)
        #expect(store.followUps.first?.timeZone == "America/Los_Angeles")
        try store.closeFollowUp(id: followUpID, status: .cancelled)
        try store.closeFollowUp(id: followUpID, status: .cancelled)
        #expect(store.checks.count == 1)
        #expect(throws: WorkflowError.closedFollowUp) { try store.rescheduleFollowUp(id: followUpID, due: due, timeZone: zone) }
        #expect(throws: WorkflowError.closedFollowUp) { try store.closeFollowUp(id: followUpID, status: .completed) }
    }

    @Test func missingPersonAndStaleRecordDoNotCreateWork() throws {
        let (store, _) = memory()
        #expect(throws: WorkflowError.missingPerson) { try store.begin(personID: UUID(), origin: .manual, timeZone: zone) }
        #expect(throws: WorkflowError.missingCheck) { try store.beginCorrection(checkID: UUID()) }
        #expect(store.draft == nil)
        #expect(store.checks.isEmpty)
    }
}

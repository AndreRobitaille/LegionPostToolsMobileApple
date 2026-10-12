import Foundation
import Testing
@testable import BuddyCheckCore

@MainActor private final class SuggestionMemory: SnapshotPersistence {
    var value: LocalSnapshot?
    var fail = false
    func load() throws -> LocalSnapshot? { value }
    func save(_ snapshot: LocalSnapshot) throws {
        if fail { throw CocoaError(.fileWriteOutOfSpace) }
        value = snapshot
    }
}
@MainActor private final class ChangingSuggestionSource: SuggestionSource {
    var batch: SuggestionBatch
    var fail = false
    init(_ batch: SuggestionBatch) { self.batch = batch }
    func load() throws -> SuggestionBatch {
        if fail { throw CocoaError(.fileReadUnknown) }
        return batch
    }
}
@Suite @MainActor struct SuggestionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let people = SyntheticDirectory.people
    var robert: UUID { people[0].id }
    var elena: UUID { people[1].id }
    var james: UUID { people[2].id }
    func days(_ value: Int) -> Date { now.addingTimeInterval(Double(value) * 86400) }
    func batch(_ evidence: [SuggestionEvidence]) -> SuggestionBatch {
        SuggestionBatch(observedAt: now, validUntil: days(1), candidates: evidence)
    }
    func empty(_ id: UUID, days count: Int = -180) -> SuggestionEvidence {
        SuggestionEvidence(personID: id, historySince: days(count))
    }
    func absence() -> [MeetingEvidence] {
        [MeetingEvidence(date: days(-60), presence: .absent, complete: true),
         MeetingEvidence(date: days(-30), presence: .absent, complete: true)]
    }
    func evaluate(_ evidence: [SuggestionEvidence], state: LocalSnapshot = .init(), skipped: Set<UUID> = []) -> SuggestionResult {
        SuggestionEngine.evaluate(batch(evidence), people: people, snapshot: state, skipped: skipped, now: now)
    }
    func choice(_ result: SuggestionResult) throws -> MemberSuggestion {
        guard case .person(let person) = result else { Issue.record("Expected a suggested person, got \(result)"); throw WorkflowError.missingPerson }
        return person
    }
    private func makeStore(_ persistence: SuggestionMemory = SuggestionMemory()) -> CheckStore {
        CheckStore(persistence: persistence, now: { now })
    }
    func record(_ store: CheckStore, id: UUID, outcome: CheckOutcome, age: Int, followUp: Bool = false) throws -> UUID {
        let check = try store.begin(personID: id, origin: .manual, timeZone: "America/Chicago")
        try store.updateDraft(id: check) { $0.outcome = outcome; $0.occurredAt = days(-age) }
        if followUp { try store.chooseReminder(id: check, timeZone: "America/Chicago") }
        try store.saveDraft(id: check, includeFollowUp: followUp)
        return check
    }

    @Test func knownEmptyThenUnansweredThenOlderConversationWithStableTies() throws {
        let conversation = SuggestionEvidence(personID: robert, historySince: days(-200), hasRecordedCheck: true, lastConversation: days(-120))
        let attempt = SuggestionEvidence(personID: elena, historySince: days(-180), hasRecordedCheck: true, lastAttempt: days(-40))
        let noChecks = empty(james)
        #expect(try choice(evaluate([conversation, attempt, noChecks])).personID == james)
        #expect(try choice(evaluate([conversation, attempt])).personID == elena)
        #expect(try choice(evaluate([conversation])).reasons == [.lastConversation(days(-120))])
        #expect(try choice(evaluate([empty(elena), empty(robert)])).personID == robert)
        #expect(try choice(evaluate([empty(robert), empty(elena)])).personID == robert)
        var absent = empty(elena); absent.meetings = absence()
        #expect(try choice(evaluate([empty(robert), absent])).personID == elena)
        #expect(try choice(evaluate([empty(robert, days: -200), empty(elena)])).personID == robert)
    }

    @Test func recentAttemptAndConversationHaveSeparateExactExpiryBoundaries() throws {
        var evidence = empty(robert)
        evidence.lastAttempt = days(-6)
        #expect(evaluate([evidence]) == .none)
        evidence.lastAttempt = days(-7)
        #expect(try choice(evaluate([evidence])).reasons == [.noConversation(since: days(-180))])
        evidence.lastConversation = days(-59); evidence.lastAttempt = nil; evidence.meetings = absence()
        #expect(evaluate([evidence]) == .none)
        evidence.lastConversation = days(-60)
        #expect(try choice(evaluate([evidence])).personID == robert)
    }

    @Test func absentRequiresLatestTwoCompleteGeneralMemberRegisters() throws {
        var evidence = SuggestionEvidence(personID: james, meetings: absence())
        let suggestion = try choice(evaluate([evidence]))
        #expect(suggestion.reasons == [.absentMeetings([days(-60), days(-30)])])
        #expect(suggestion.incompleteHistory)
        for presence in [MeetingPresence.present, .excused, .notRecorded] {
            evidence.meetings = absence() + [MeetingEvidence(date: days(-2), presence: presence, complete: true)]
            #expect(evaluate([evidence]) == .insufficientEvidence)
        }
        evidence.meetings = absence(); evidence.meetings[1].complete = false
        #expect(evaluate([evidence]) == .insufficientEvidence)
        evidence.meetings = absence(); evidence.meetings[1].generalMembership = false
        #expect(evaluate([evidence]) == .insufficientEvidence)
        evidence.meetings = [absence()[0], absence()[0]]
        #expect(evaluate([evidence]) == .insufficientEvidence)
        evidence.meetings[1].date = evidence.meetings[0].date.addingTimeInterval(60)
        #expect(evaluate([evidence]) == .insufficientEvidence)
        evidence.meetings = Array(absence().prefix(1))
        #expect(evaluate([evidence]) == .insufficientEvidence)
    }

    @Test func partialUnknownAndInvalidEvidenceCannotClaimNoChecks() throws {
        #expect(evaluate([SuggestionEvidence(personID: robert)]) == .insufficientEvidence)
        #expect(try choice(evaluate([empty(robert)])).reasons == [.noChecks(since: days(-180))])
        var future = empty(robert); future.lastConversation = days(1)
        #expect(evaluate([future]) == .insufficientEvidence)
        #expect(evaluate([empty(robert), empty(robert)]) == .failed)
        var stale = batch([empty(robert)]); stale.validUntil = now
        #expect(SuggestionEngine.evaluate(stale, people: people, snapshot: .init(), skipped: [], now: now) == .stale)
        stale.observedAt = days(1); stale.validUntil = days(2)
        #expect(SuggestionEngine.evaluate(stale, people: people, snapshot: .init(), skipped: [], now: now) == .stale)
    }

    @Test func changedEligibilityRealPeopleAndUnknownIdentitiesAreExcluded() throws {
        for eligibility in [SuggestionEligibility.assignedElsewhere, .contactPaused, .unavailable] {
            var evidence = empty(robert); evidence.eligibility = eligibility
            #expect(evaluate([evidence]) == .none)
        }
        #expect(evaluate([empty(UUID())]) == .none)
        var realPerson = people[0]; realPerson.isSynthetic = false
        #expect(SuggestionEngine.evaluate(batch([empty(robert)]), people: [realPerson], snapshot: .init(), skipped: [], now: now) == .none)
    }

    @Test func localOutcomesCorrectionsDraftsAndOpenFollowUpsChangeSuggestions() throws {
        let store = makeStore()
        let id = try record(store, id: robert, outcome: .connected, age: 2)
        #expect(evaluate([empty(robert)], state: store.snapshot) == .none)
        try store.beginCorrection(checkID: id)
        try store.updateDraft(id: id) { $0.outcome = .notAttempted }
        // An unfinished correction defers the person too.
        #expect(evaluate([empty(robert)], state: store.snapshot) == .none)
        try store.saveDraft(id: id, includeFollowUp: false)
        #expect(try choice(evaluate([empty(robert)], state: store.snapshot)).reasons == [.noConversation(since: days(-180))])
        try store.beginCorrection(checkID: id)
        try store.updateDraft(id: id) { $0.outcome = .noAnswer }
        try store.saveDraft(id: id, includeFollowUp: false)
        #expect(evaluate([empty(robert)], state: store.snapshot) == .none)
        #expect(store.checks.count == 1)
        let older = try record(store, id: elena, outcome: .noAnswer, age: 20, followUp: true)
        #expect(evaluate([empty(elena)], state: store.snapshot) == .none)
        let followUp = try #require(store.followUp(forCheck: older))
        try store.closeFollowUp(id: followUp.id, status: .cancelled)
        #expect(try choice(evaluate([empty(elena)], state: store.snapshot)).personID == elena)
    }

    @Test func someoneElseExhaustsWithoutCyclingAndRefreshPreservesSkips() throws {
        let source = ChangingSuggestionSource(batch([empty(elena), empty(robert)]))
        let session = SuggestionSession(source: source, now: { now }); let store = makeStore()
        session.refresh(); #expect(try choice(session.result(store: store)).personID == robert)
        session.skip(robert); session.refresh()
        #expect(try choice(session.result(store: store)).personID == elena)
        session.skip(elena); #expect(session.result(store: store) == .exhausted)
        session.refresh(); #expect(session.result(store: store) == .exhausted)
        session.startAgain(); #expect(try choice(session.result(store: store)).personID == robert)
    }

    @Test func selectionRechecksAuthorityAndDoesNotWriteARecord() throws {
        let source = ChangingSuggestionSource(batch([empty(robert)]))
        let session = SuggestionSession(source: source, now: { now }); let store = makeStore()
        session.refresh(); let before = store.snapshot
        #expect(session.select(robert, store: store)); #expect(store.snapshot == before)
        source.batch.candidates[0].eligibility = .contactPaused
        #expect(!session.select(robert, store: store)); #expect(session.result(store: store) == .none)
        source.batch.candidates = []; #expect(!session.select(robert, store: store))
        source.batch = batch([empty(robert)]); session.refresh()
        source.fail = true
        #expect(!session.select(robert, store: store)); #expect(session.batch == nil)
        #expect(session.result(store: store) == .failed); #expect(store.snapshot == before)
        source.fail = false; session.refresh()
        #expect(session.select(robert, store: store))
    }

    @Test func staleSourceAndElapsedClockRequireRefresh() throws {
        var clock = now
        let source = ChangingSuggestionSource(batch([empty(robert)]))
        let session = SuggestionSession(source: source, now: { clock }); let store = makeStore()
        session.refresh(); clock = days(1)
        #expect(session.result(store: store) == .stale)
        #expect(!session.select(robert, store: store))
        source.batch.observedAt = clock; source.batch.validUntil = days(2)
        session.refresh(); #expect(session.select(robert, store: store))
    }

    @Test func snoozePersistsExpiresAndCanBeUndoneWithoutChangingOtherWork() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let persistence = JSONSnapshotPersistence(fileURL: folder.appendingPathComponent("state.json"))
        let store = CheckStore(persistence: persistence, now: { now })
        try store.rememberContact(person: people[0], contactID: "synthetic-contact", managed: .init())
        try store.begin(personID: elena, origin: .manual, timeZone: "America/Chicago")
        let before = store.snapshot
        try store.snoozeSuggestion(personID: robert)
        let reopened = CheckStore(persistence: persistence, now: { now })
        #expect(reopened.snapshot.suggestionSnoozes == [.init(personID: robert, until: days(7))])
        #expect(reopened.draft == before.draft); #expect(reopened.snapshot.contactLinks == before.contactLinks)
        #expect(evaluate([empty(robert)], state: reopened.snapshot) == .none)
        var fresh = batch([empty(robert)]); fresh.observedAt = days(7); fresh.validUntil = days(8)
        #expect(try choice(SuggestionEngine.evaluate(fresh, people: people, snapshot: reopened.snapshot, skipped: [], now: days(7))).personID == robert)
        try reopened.showSuggestionAgain(personID: robert)
        #expect(reopened.snapshot == before)
        let memory = SuggestionMemory(); let failing = makeStore(memory)
        memory.fail = true
        #expect(throws: CocoaError.self) { try failing.snoozeSuggestion(personID: robert) }
        #expect(failing.snapshot.suggestionSnoozes.isEmpty)
    }

    @Test func versionTwoMigrationPreservesLinksChecksAndFollowUps() throws {
        let store = makeStore()
        _ = try record(store, id: robert, outcome: .noAnswer, age: 10, followUp: true)
        try store.rememberContact(person: people[0], contactID: "synthetic-contact", managed: .init(phoneID: "phone-field"))
        try store.begin(personID: elena, origin: .manual, timeZone: "America/Chicago")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(store.snapshot)) as? [String: Any])
        object["formatVersion"] = 2; object.removeValue(forKey: "suggestionSnoozes")
        let migrated = try JSONDecoder().decode(LocalSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(migrated == store.snapshot); #expect(migrated.formatVersion == 5)
        #expect(migrated.suggestionSnoozes.isEmpty)
    }
}

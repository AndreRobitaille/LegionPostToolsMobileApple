import Foundation
import Testing
@testable import BuddyCheckAPI

@Suite @MainActor struct MutationTests {
    @Test func invalidTimesStayEditableInsteadOfBecomingPending() throws {
        var draft = try ConnectedDraft(personID: 42, now: fixtureTime)
        draft.outcome = .reached
        draft.occurredAt = fixtureTime.addingTimeInterval(1)
        #expect(throws: ClientError.invalidInput) { try draft.mutation(now: fixtureTime) }
        draft.occurredAt = fixtureTime
        draft.followUp = try FollowUpTime(dueAt: fixtureTime, entryZone: "America/Chicago")
        #expect(throws: ClientError.invalidInput) { try draft.mutation(now: fixtureTime) }
        draft.followUp = nil
        #expect(try draft.mutation(now: fixtureTime).id == draft.id)
    }
    @Test func restoredDateOnlyCorrectionKeepsLogicalIdentityAndPrecision() throws {
        let source = contactJSON.replacingOccurrences(of: #""precision":"instant""#, with: #""precision":"date""#)
            .replacingOccurrences(of: #""occurred_at":"2026-10-11T20:30:00.000000Z""#, with: #""occurred_at":null"#)
            .replacingOccurrences(of: #""entry_zone":"America/Chicago""#, with: #""entry_zone":null"#)
        let record = try WireJSON.decoder().decode(ContactRecord.self, from: Data(source.utf8))
        var draft = try ConnectedDraft(correcting: record, now: fixtureTime)
        draft.outcome = .reached
        let restored = try JSONDecoder().decode(ConnectedDraft.self, from: JSONEncoder().encode(draft))
        let operation = try restored.mutation()
        let object = try #require(JSONSerialization.jsonObject(with: operation.body) as? [String: Any])
        let facts = try #require(object["facts"] as? [String: Any])
        #expect(operation.route.path == "buddy-checks/81/corrections")
        #expect(object["expected_revision"] as? Int == 1)
        #expect(facts["occurred_on"] as? String == "2026-10-11")
        #expect(facts["occurred_at"] == nil && facts["entry_zone"] == nil)
        #expect(facts["outcome"] as? String == "reached")
        #expect(object["follow_up"] == nil && object["person_id"] == nil)
    }
    @Test func followUpAndSnoozeMutationsMatchImplementedContract() throws {
        let followUp = try WireJSON.decoder().decode(FollowUpRecord.self, from: Data(#"{"id":14,"person_id":42,"contact_id":null,"due_at":"2026-10-12T20:30:00Z","entry_zone":"America/Chicago","status":"open","revision":3}"#.utf8))
        let change = try PendingMutation.change(followUp, action: .complete)
        let object = try #require(JSONSerialization.jsonObject(with: change.body) as? [String: Any])
        #expect(change.route.path == "buddy-checks/follow-ups/14/changes")
        #expect(object["action"] as? String == "complete")
        #expect(object["expected_revision"] as? Int == 3)
        #expect(object["due_at"] == nil && object["facts"] == nil && object["person_id"] == nil)
        let snooze = try WireJSON.decoder().decode(SnoozeRecord.self, from: Data(#"{"id":19,"person_id":42,"until_at":"2026-10-12T20:30:00Z","cancelled_at":null,"revision":0}"#.utf8))
        let undo = try PendingMutation.undo(snooze)
        #expect(undo.route.path == "buddy-checks/snoozes/19" && undo.route.method == "DELETE")
        let undoObject = try #require(JSONSerialization.jsonObject(with: undo.body) as? [String: Any])
        #expect(Set(undoObject.keys) == ["operation_id", "expected_revision"])
    }
    @Test func partialReceiptCannotClaimRequestedFollowUpAccepted() async throws {
        let facts = try CheckFacts(channel: .phone, outcome: .noAnswer, occurredAt: fixtureTime, entryZone: "America/Chicago")
        let operation = try PendingMutation.record(personID: 42, facts: facts, followUp: FollowUpTime(dueAt: fixtureTime.addingTimeInterval(86400), entryZone: "America/Chicago"), operationID: operationID)
        let transport = StubTransport([response(receiptJSON, status: 201)])
        await #expect(throws: ClientError.invalidResponse) {
            try await BuddyCheckClient(configuration: configuration(), transport: transport).submit(operation, token: "t")
        }
    }
    @Test func definiteRejectionCanBeDiscardedButUnknownSubmissionCannot() async throws {
        let disk = TestJournal(); let journal = try SubmissionJournal(scope: scope(), persistence: disk)
        try journal.rememberContact(personID: 42, link: .init(contactID: "synthetic-device-id", creationPending: true))
        let operation = try mutation(); try journal.prepare(operation)
        #expect(throws: ClientError.unfinishedOperation) { try journal.discardRejectedSubmission() }
        let transport = StubTransport([response(#"{"error":{"code":"not_found"}}"#, status: 404), response(cardJSON),
                                       response(#"{"error":{"code":"invalid_request"}}"#, status: 422)])
        await #expect(throws: ClientError.server(status: 422, code: "invalid_request")) {
            try await journal.reconcile(client: BuddyCheckClient(configuration: configuration(), transport: transport), token: "t")
        }
        #expect(journal.snapshot.pending == operation)
        try journal.discardRejectedSubmission()
        #expect(journal.snapshot.pending == nil)
        #expect(journal.snapshot.contactLinks?[42]?.contactID == "synthetic-device-id")
        let restored = try SubmissionJournal(scope: scope(), persistence: disk)
        #expect(restored.snapshot.contactLinks?[42]?.creationPending == true)
    }
}

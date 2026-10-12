import Foundation
import Testing
@testable import BuddyCheckAPI

@Suite @MainActor struct StaleCorrectionTests {
    private func record(revision: Int = 1, legacy: Bool = false, personID: Int = 42, contactID: Int = 81) throws -> ContactRecord {
        var json = contactJSON.replacingOccurrences(of: #""revision":1"#, with: "\"revision\":\(revision)")
            .replacingOccurrences(of: #""person_id":42"#, with: "\"person_id\":\(personID)")
            .replacingOccurrences(of: #""id":81"#, with: "\"id\":\(contactID)")
        if legacy {
            json = json.replacingOccurrences(of: #""precision":"instant""#, with: #""precision":"date""#)
                .replacingOccurrences(of: #""occurred_at":"2026-10-11T20:30:00.000000Z""#, with: #""occurred_at":null"#)
                .replacingOccurrences(of: #""entry_zone":"America/Chicago""#, with: #""entry_zone":null"#)
        }
        return try WireJSON.decoder().decode(ContactRecord.self, from: Data(json.utf8))
    }
    private func reject(_ journal: SubmissionJournal, code: String = "stale_revision") async throws {
        let transport = StubTransport([response(#"{"error":{"code":"not_found"}}"#, status: 404), response(cardJSON),
                                       response("{\"error\":{\"code\":\"\(code)\"}}", status: 409)])
        await #expect(throws: ClientError.server(status: 409, code: code)) {
            try await journal.reconcile(client: BuddyCheckClient(configuration: configuration(), transport: transport), token: "synthetic")
        }
    }
    private func draft(legacy: Bool = false) throws -> ConnectedDraft {
        var draft = try ConnectedDraft(correcting: record(legacy: legacy))
        draft.channel = .text; draft.outcome = .reached; draft.notes = "Keep my unsent synthetic correction"
        return draft
    }
    @Test(arguments: [false, true]) func reviewedReplacementKeepsFactsAndRestoresWithNewIdentity(legacy: Bool) async throws {
        let disk = TestJournal(); let journal = try SubmissionJournal(scope: scope(), persistence: disk)
        let original = try draft(legacy: legacy)
        try journal.saveDraft(original); let pending = try original.mutation(); try journal.prepare(pending)
        try journal.rememberContact(personID: 42, link: .init(contactID: "local-link"))
        try await reject(journal)
        #expect(journal.canReviewStaleCorrection)
        let replacement = try journal.continueCorrection(afterReviewing: record(revision: 2, legacy: legacy))
        #expect(replacement.id != pending.id)
        #expect(replacement.personID == original.personID && replacement.channel == original.channel)
        #expect(replacement.outcome == original.outcome && replacement.notes == original.notes)
        #expect(replacement.occurredAt == original.occurredAt && replacement.entryZone == original.entryZone)
        #expect(replacement.correction?.legacyDate == original.correction?.legacyDate)
        #expect(replacement.correction?.expectedRevision == 2)
        #expect(journal.snapshot.pending == nil && journal.lastReceipt == nil && journal.rejection == nil)
        let restored = try SubmissionJournal(scope: scope(), persistence: disk)
        #expect(restored.snapshot.draft == replacement && restored.snapshot.pending == nil)
        #expect(restored.snapshot.contactLinks?[42]?.contactID == "local-link")
        let body = try #require(JSONSerialization.jsonObject(with: replacement.mutation().body) as? [String: Any])
        let facts = try #require(body["facts"] as? [String: Any])
        #expect(body["expected_revision"] as? Int == 2)
        #expect(facts["notes"] as? String == original.notes && facts["channel"] as? String == "text")
        #expect(facts["outcome"] as? String == "reached")
        if legacy { #expect(facts["occurred_on"] as? String == "2026-10-11" && facts["occurred_at"] == nil) }
        else { #expect(facts["occurred_at"] != nil && facts["occurred_on"] == nil) }
        // Explicit save, not review/continue, is the step that submits the new operation.
        let operation = try replacement.mutation()
        try restored.prepare(operation)
        let accepted = receiptJSON.replacingOccurrences(of: operationID.uuidString.lowercased(), with: operation.id.uuidString.lowercased())
            .replacingOccurrences(of: #""revision":1"#, with: #""revision":3"#)
            .replacingOccurrences(of: "Synthetic attempt", with: replacement.notes)
            .replacingOccurrences(of: #""outcome":"no_answer""#, with: #""outcome":"reached""#)
            .replacingOccurrences(of: #""channel":"phone""#, with: #""channel":"text""#)
        let transport = StubTransport([response(#"{"error":{"code":"not_found"}}"#, status: 404), response(cardJSON), response(accepted, status: 201)])
        _ = try await restored.reconcile(client: BuddyCheckClient(configuration: configuration(), transport: transport), token: "synthetic")
        let requests = await transport.captured()
        #expect(requests.count == 3 && requests.last?.httpBody == operation.body)
        #expect(requests.last?.url?.path == "/api/mobile/v1/buddy-checks/81/corrections")
        #expect(restored.snapshot.pending == nil && restored.snapshot.draft == nil)
    }
    @Test func unconfirmedOrConflictingOperationCannotBeReplaced() async throws {
        let disk = TestJournal(); let journal = try SubmissionJournal(scope: scope(), persistence: disk)
        let original = try draft(); try journal.saveDraft(original); try journal.prepare(original.mutation())
        #expect(throws: ClientError.unfinishedOperation) { try journal.continueCorrection(afterReviewing: record(revision: 2)) }
        try await reject(journal, code: "operation_payload_conflict")
        #expect(!journal.canReviewStaleCorrection)
        #expect(throws: ClientError.unfinishedOperation) { try journal.continueCorrection(afterReviewing: record(revision: 2)) }
        try await reject(journal)
        let restored = try SubmissionJournal(scope: scope(), persistence: disk)
        #expect(restored.snapshot.pending == journal.snapshot.pending)
        #expect(!restored.canReviewStaleCorrection)
        #expect(throws: ClientError.unfinishedOperation) { try restored.continueCorrection(afterReviewing: record(revision: 2)) }
        try await reject(restored)
        #expect(restored.canReviewStaleCorrection)
    }
    @Test func wrongRecordOldRevisionAndDiskFailureRetainRejectedWork() async throws {
        let disk = TestJournal(); let journal = try SubmissionJournal(scope: scope(), persistence: disk)
        let original = try draft(); try journal.saveDraft(original); try journal.prepare(original.mutation())
        try await reject(journal)
        let before = journal.snapshot
        for current in [try record(revision: 2, personID: 43), try record(revision: 2, contactID: 82), try record()] {
            #expect(throws: ClientError.invalidInput) { try journal.continueCorrection(afterReviewing: current) }
            #expect(journal.snapshot == before && journal.canReviewStaleCorrection)
        }
        disk.failWrites = true
        #expect(throws: ClientError.journalUnavailable) { try journal.continueCorrection(afterReviewing: record(revision: 2)) }
        #expect(journal.snapshot == before && disk.value == before && journal.canReviewStaleCorrection)
        disk.failWrites = false
        _ = try journal.continueCorrection(afterReviewing: record(revision: 2))
        #expect(journal.snapshot.draft?.id != original.id && journal.snapshot.pending == nil)
    }
}

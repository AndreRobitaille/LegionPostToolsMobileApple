import Foundation
import Testing
@testable import BuddyCheckAPI

@Suite struct HomeActivityTests {
    private func followUp(_ id: Int, day: Int, status: String = "open", revision: Int = 0) -> String {
        """
        {"id":\(id),"person_id":42,"contact_id":null,"due_at":"2026-10-\(day)T20:30:00Z","entry_zone":"America/Chicago","status":"\(status)","revision":\(revision)}
        """
    }
    private func page(_ items: [String], cursor: String? = nil) -> String {
        "{\"items\":[\(items.joined(separator: ","))],\"next_cursor\":\(cursor.map { "\"\($0)\"" } ?? "null")}"
    }
    @Test func nextFollowUpUsesAllPagesAndLatestStatusBeforeChoosingEarliestDue() async throws {
        let transport = StubTransport([
            response(page([followUp(1, day: 15), followUp(2, day: 13)], cursor: "25")),
            response(page([followUp(2, day: 13, status: "completed", revision: 1), followUp(3, day: 14)]))
        ])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        #expect(try await client.nextOpenFollowUp(token: "synthetic")?.id == 3)
        let requests = await transport.captured()
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.path.hasSuffix("buddy-checks/follow-ups") == true })
        #expect(requests.last?.url?.query?.contains("cursor=25") == true)
    }
    @Test func incompleteAndLoopingPagesCannotBecomeAnEmptyOrPartialSummary() async throws {
        for looping in [false, true] {
            let first = page([followUp(1, day: 15)], cursor: "25")
            let transport = StubTransport([response(first), looping ? response(first) : .failure(.connectionUnavailable)])
            let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
            await #expect(throws: looping ? ClientError.invalidResponse : .connectionUnavailable) {
                try await client.nextOpenFollowUp(token: "synthetic")
            }
        }
    }
    @Test func recentChecksDeduplicatesCorrectionsAndRanksRecordedTimeNotPageOrEventTime() async throws {
        let old = contactJSON
        let corrected = old.replacingOccurrences(of: "\"revision\":1", with: "\"revision\":2")
            .replacingOccurrences(of: "no_answer", with: "reached")
            .replacingOccurrences(of: "20:31:00", with: "20:35:00")
        let other = old.replacingOccurrences(of: "\"id\":81", with: "\"id\":82")
            .replacingOccurrences(of: "20:31:00", with: "20:34:00")
        let transport = StubTransport([response(page([old, other], cursor: "25")), response(page([corrected, old]))])
        let records = try await BuddyCheckClient(configuration: configuration(), transport: transport).recentChecks(token: "synthetic")
        #expect(records.map(\.id) == [81, 82])
        #expect(records.first?.outcome == "reached" && records.first?.revision == 2)
    }
    @Test func correctionUsesFreshRevisionAndRejectsIdentityChange() async throws {
        let initial = try WireJSON.decoder().decode(ContactRecord.self, from: Data(contactJSON.utf8))
        let newer = contactJSON.replacingOccurrences(of: "\"revision\":1", with: "\"revision\":2")
        let transport = StubTransport([response(cardJSON), response(page([contactJSON], cursor: "25")), response(page([newer]))])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        #expect(try await client.latestContact(initial, token: "synthetic").revision == 2)
        let wrong = newer.replacingOccurrences(of: "\"person_id\":42", with: "\"person_id\":43")
        let rejected = BuddyCheckClient(configuration: try configuration(), transport: StubTransport([response(cardJSON), response(page([wrong]))]))
        await #expect(throws: ClientError.invalidResponse) { try await rejected.latestContact(initial, token: "synthetic") }
    }
}

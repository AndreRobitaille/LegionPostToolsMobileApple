import Foundation
import Testing
@testable import BuddyCheckAPI

@Suite struct FollowUpRefreshTests {
    private let original = #"{"id":14,"person_id":42,"contact_id":81,"due_at":"2026-10-12T20:30:00Z","entry_zone":"America/Chicago","status":"open","revision":3}"#
    private func record(_ value: String) throws -> FollowUpRecord {
        try WireJSON.decoder().decode(FollowUpRecord.self, from: Data(value.utf8))
    }
    private func page(_ values: [String], cursor: String? = nil) -> Result<HTTPResponse, ClientError> {
        response("{\"items\":[" + values.joined(separator: ",") + "],\"next_cursor\":" + (cursor.map { "\"\($0)\"" } ?? "null") + "}")
    }
    @Test func findsCurrentClosedRecordOnLaterPageWithoutMutating() async throws {
        let closed = original.replacingOccurrences(of: "open", with: "completed").replacingOccurrences(of: #""revision":3"#, with: #""revision":4"#)
        let unrelated = original.replacingOccurrences(of: #""id":14"#, with: #""id":2"#)
        let transport = StubTransport([page([unrelated], cursor: "2"), page([closed])])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        let current = try await client.currentFollowUp(record(original), token: "synthetic-token")
        #expect(current.status == .completed && current.revision == 4 && current.id == 14)
        let requests = await transport.captured()
        #expect(requests.count == 2 && requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
        #expect(requests.allSatisfy { $0.url?.path == "/api/mobile/v1/buddy-checks/follow-ups" })
        #expect(URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "cursor", value: "2")) == true)
    }
    @Test(arguments: ["person", "older", "zone", "duplicate"])
    func rejectsInconsistentCurrentRecord(_ fault: String) async throws {
        let changed: String
        switch fault {
        case "person": changed = original.replacingOccurrences(of: #""person_id":42"#, with: #""person_id":43"#)
        case "older": changed = original.replacingOccurrences(of: #""revision":3"#, with: #""revision":2"#)
        case "zone": changed = original.replacingOccurrences(of: "America/Chicago", with: "No/SuchZone")
        default: changed = original
        }
        let transport = StubTransport([page(fault == "duplicate" ? [original, changed] : [changed])])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        await #expect(throws: ClientError.invalidResponse) { try await client.currentFollowUp(record(original), token: "t") }
        #expect(await transport.captured().count == 1)
    }
    @Test func missingAndFailedReadsNeverReturnSelectedOldFacts() async throws {
        let transport = StubTransport([page([]), .failure(.connectionUnavailable), response(#"{"error":{"code":"revoked_session"}}"#, status: 401)])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        await #expect(throws: ClientError.server(status: 404, code: "not_found")) { try await client.currentFollowUp(record(original), token: "t") }
        await #expect(throws: ClientError.connectionUnavailable) { try await client.currentFollowUp(record(original), token: "t") }
        await #expect(throws: ClientError.server(status: 401, code: "revoked_session")) { try await client.currentFollowUp(record(original), token: "t") }
    }
    @Test func repeatedCursorStopsWithoutAnEndlessRead() async throws {
        let transport = StubTransport([page([], cursor: "2"), page([], cursor: "2")])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        await #expect(throws: ClientError.invalidResponse) { try await client.currentFollowUp(record(original), token: "t") }
        #expect(await transport.captured().count == 2)
    }
    @Test func newlyCreatedFollowUpUsesRevisionZero() async throws {
        let first = original.replacingOccurrences(of: #""revision":3"#, with: #""revision":0"#)
        let transport = StubTransport([page([first])])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        let current = try await client.currentFollowUp(record(first), token: "t")
        #expect(current.revision == 0 && current.status == .open)
        let operation = try PendingMutation.change(current, action: .complete)
        #expect(operation.expectedRevision == 0)
        #expect(await transport.captured().count == 1)
    }
}

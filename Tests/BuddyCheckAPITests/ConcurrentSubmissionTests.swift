import Foundation
import Testing
@testable import BuddyCheckAPI

/// Holds one actual await boundary instead of depending on sleeps or task timing.
private actor SubmissionGate: HTTPTransport {
    let heldRequest: Int
    private var requests: [URLRequest] = []
    private var waiter: CheckedContinuation<Void, Never>?
    private var held: CheckedContinuation<Void, Never>?
    private var arrived = false

    init(heldRequest: Int) { self.heldRequest = heldRequest }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        let index = requests.count
        if index == heldRequest {
            arrived = true
            await withCheckedContinuation { continuation in
                held = continuation
                waiter?.resume(); waiter = nil
            }
        }
        switch index {
        case 1: return try response(#"{"error":{"code":"not_found"}}"#, status: 404).get()
        case 2: return try response(cardJSON).get()
        case 3: return try response(receiptJSON, status: 201).get()
        default: return try response(receiptJSON).get()
        }
    }
    func waitUntilHeld() async {
        if arrived { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() { held?.resume(); held = nil }
    func captured() -> [URLRequest] { requests }
}

@Suite @MainActor struct ConcurrentSubmissionTests {
    @Test(arguments: [1, 2, 3])
    func repeatedSaveCannotOverlapReceiptAuthorityOrSubmission(heldRequest: Int) async throws {
        let disk = TestJournal()
        let journal = try SubmissionJournal(scope: scope(), persistence: disk)
        let operation = try mutation()
        try journal.prepare(operation)
        let transport = SubmissionGate(heldRequest: heldRequest)
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        let first = Task { try await journal.reconcile(client: client, token: "synthetic") }
        await transport.waitUntilHeld()

        // Repeated Save, Check submission and unfinished-work actions must not
        // start another request or replace the immutable operation while waiting.
        #expect(journal.isSubmitting)
        let before = journal.snapshot
        await #expect(throws: ClientError.invalidInput) {
            try await journal.reconcile(client: client, token: "synthetic")
        }
        #expect(throws: ClientError.unfinishedOperation) { try journal.prepare(operation) }
        #expect(throws: ClientError.unfinishedOperation) { try journal.discardDraft() }
        #expect(journal.snapshot == before && disk.value == before)
        #expect(await transport.captured().count == heldRequest)
        await transport.release()

        let accepted = try await first.value
        #expect(accepted.operationId == operation.id)
        #expect(journal.snapshot.pending == nil && journal.lastReceipt == accepted)
        #expect(!journal.isSubmitting)
        let requests = await transport.captured()
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST"])
        #expect(requests.last?.httpBody == operation.body)

        // A repeated recovery after acceptance, including reconstruction from
        // persistence, cannot resubmit an already-cleared operation.
        await #expect(throws: ClientError.invalidInput) {
            try await journal.reconcile(client: client, token: "synthetic")
        }
        let restored = try SubmissionJournal(scope: scope(), persistence: disk)
        await #expect(throws: ClientError.invalidInput) {
            try await restored.reconcile(client: client, token: "synthetic")
        }
        #expect(await transport.captured().count == 3)

        // Even explicit reuse of the same immutable operation recovers its receipt
        // instead of creating a new identity or issuing a second contact POST.
        try restored.prepare(operation)
        let recovered = try await restored.reconcile(client: client, token: "synthetic")
        #expect(recovered == accepted && restored.snapshot.pending == nil)
        let finalRequests = await transport.captured()
        #expect(finalRequests.map(\.httpMethod) == ["GET", "GET", "POST", "GET"])
        #expect(finalRequests.last?.url?.path == "/api/mobile/v1/buddy-checks/receipts/" + operation.id.uuidString.lowercased())
    }
}

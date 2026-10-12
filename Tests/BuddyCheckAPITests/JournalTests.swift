import Foundation
import Testing
@testable import BuddyCheckAPI

@MainActor final class TestVault: SecretVault {
    var values: [String: Data] = [:]
    var failWrites = false
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws {
        if failWrites { throw ClientError.journalUnavailable }
        values[key] = data
    }
    func remove(_ key: String) throws { values.removeValue(forKey: key) }
}
@MainActor final class TestJournal: JournalPersistence {
    var value: JournalSnapshot?
    var failWrites = false
    func load(scope: AccountScope) throws -> JournalSnapshot? { value }
    func save(_ snapshot: JournalSnapshot) throws {
        if failWrites { throw ClientError.journalUnavailable }
        value = snapshot
    }
    func purge(scope: AccountScope) throws { value = nil }
}
func scope(user: Int = 7) throws -> AccountScope {
    let session = try WireJSON.decoder().decode(MobileSession.self, from: Data(sessionJSON.replacingOccurrences(of: #""id":7"#, with: "\"id\":\(user)").utf8))
    return try AccountScope(configuration: configuration(), session: session)
}

@Suite @MainActor struct JournalTests {
    @Test func encryptsRoundTripRejectsTamperingAndSeparatesAccounts() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let vault = TestVault()
        let disk = EncryptedJournal(directory: folder, vault: vault)
        var draft = try ConnectedDraft(personID: 42, now: fixtureTime)
        draft.notes = "Private synthetic text not present in ciphertext"
        let snapshot = JournalSnapshot(scope: try scope(), draft: draft, pending: try mutation())
        try disk.save(snapshot)
        #expect(try disk.load(scope: scope()) == snapshot)
        let bytes = try Data(contentsOf: disk.fileURL(scope()))
        #expect(bytes.range(of: Data(draft.notes.utf8)) == nil)
        #expect(try disk.load(scope: scope(user: 8)) == nil)
        let backup = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(backup.isExcludedFromBackup == true)
        var damaged = bytes; damaged[damaged.count - 1] ^= 1
        try damaged.write(to: disk.fileURL(scope()))
        #expect(throws: ClientError.journalUnavailable) { try disk.load(scope: scope()) }
        #expect(try Data(contentsOf: disk.fileURL(scope())) == damaged)
        try disk.purge(scope: scope())
        #expect(vault.values.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: try disk.fileURL(scope()).path))
    }
    @Test func missingEncryptionKeyNeverReplacesExistingWork() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let vault = TestVault(); let disk = EncryptedJournal(directory: folder, vault: vault)
        let snapshot = JournalSnapshot(scope: try scope(), pending: try mutation())
        try disk.save(snapshot)
        let before = try Data(contentsOf: disk.fileURL(scope()))
        vault.values.removeAll()
        #expect(throws: ClientError.journalUnavailable) { try disk.load(scope: scope()) }
        #expect(throws: ClientError.journalUnavailable) { try disk.save(snapshot) }
        #expect(try Data(contentsOf: disk.fileURL(scope())) == before)
    }
    @Test func storageFailurePreventsPublishingNewOperation() throws {
        let disk = TestJournal(); let journal = try SubmissionJournal(scope: scope(), persistence: disk)
        disk.failWrites = true
        #expect(throws: ClientError.journalUnavailable) { try journal.prepare(mutation()) }
        #expect(journal.snapshot.pending == nil && disk.value == nil)
    }
    @Test func lostResponseRecoversReceiptWithoutSecondWrite() async throws {
        let disk = TestJournal()
        let journal = try SubmissionJournal(scope: scope(), persistence: disk)
        let original = try mutation(); try journal.prepare(original)
        let transport = StubTransport([
            response(#"{"error":{"code":"not_found"}}"#, status: 404), response(cardJSON), .failure(.connectionUnavailable),
            response(receiptJSON)
        ])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        await #expect(throws: ClientError.connectionUnavailable) { try await journal.reconcile(client: client, token: "t") }
        #expect(journal.snapshot.pending == original && journal.lastReceipt == nil)
        let restored = try SubmissionJournal(scope: scope(), persistence: disk)
        let receipt = try await restored.reconcile(client: client, token: "renewed")
        #expect(receipt.operationId == original.id)
        #expect(restored.snapshot.pending == nil && restored.lastReceipt == receipt)
        let requests = await transport.captured()
        #expect(requests.filter { $0.httpMethod == "POST" }.count == 1)
        #expect(requests.last?.url?.path.hasSuffix(original.id.uuidString.lowercased()) == true)
    }
    @Test func missingReceiptRechecksAuthorityAndRetriesExactBody() async throws {
        let disk = TestJournal(); let journal = try SubmissionJournal(scope: scope(), persistence: disk)
        let operation = try mutation(); try journal.prepare(operation)
        let transport = StubTransport([
            response(#"{"error":{"code":"not_found"}}"#, status: 404),
            response(#"{"error":{"code":"not_found"}}"#, status: 404)
        ])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        await #expect(throws: ClientError.server(status: 404, code: "not_found")) { try await journal.reconcile(client: client, token: "t") }
        #expect(await transport.captured().allSatisfy { $0.httpMethod != "POST" })
        #expect(journal.snapshot.pending == operation)
        let retry = StubTransport([response(#"{"error":{"code":"not_found"}}"#, status: 404), response(cardJSON), response(receiptJSON, status: 201)])
        _ = try await journal.reconcile(client: BuddyCheckClient(configuration: configuration(), transport: retry), token: "t")
        #expect(await retry.captured().last?.httpBody == operation.body)
    }
    @Test func acceptanceDiskFailureRetainsOperationForReceiptRecovery() async throws {
        let disk = TestJournal(); let journal = try SubmissionJournal(scope: scope(), persistence: disk)
        let operation = try mutation(); try journal.prepare(operation)
        disk.failWrites = true
        let transport = StubTransport([response(receiptJSON), response(receiptJSON)])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        await #expect(throws: ClientError.journalUnavailable) { try await journal.reconcile(client: client, token: "t") }
        #expect(journal.snapshot.pending == operation && journal.lastReceipt == nil)
        disk.failWrites = false
        _ = try await journal.reconcile(client: client, token: "t")
        #expect(journal.snapshot.pending == nil)
        #expect(await transport.captured().allSatisfy { $0.httpMethod != "POST" })
    }
    @Test func rejectsMismatchedLoadedAccountAndMismatchedReceiptPerson() async throws {
        let disk = TestJournal(); disk.value = JournalSnapshot(scope: try scope(user: 8))
        #expect(throws: ClientError.accountMismatch) { try SubmissionJournal(scope: scope(), persistence: disk) }
        disk.value = nil
        let journal = try SubmissionJournal(scope: scope(), persistence: disk)
        try journal.prepare(mutation())
        let transport = StubTransport([response(receiptJSON.replacingOccurrences(of: #""person_id":42"#, with: #""person_id":99"#))])
        await #expect(throws: ClientError.invalidResponse) {
            try await journal.reconcile(client: BuddyCheckClient(configuration: configuration(), transport: transport), token: "t")
        }
        #expect(journal.snapshot.pending != nil)
    }
}

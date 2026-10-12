import Foundation
import Testing
@testable import BuddyCheckAPI

@MainActor private final class RenewalClock {
    var now = fixtureTime
    var uptime: TimeInterval = 10_000
    func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds); uptime += seconds }
}
private actor GatedAuthTransport: HTTPTransport {
    private var responses: [Result<HTTPResponse, ClientError>]
    private var requests: [URLRequest] = []
    private let gate: Int
    private var blocked: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    init(_ responses: [Result<HTTPResponse, ClientError>], gate: Int) { self.responses = responses; self.gate = gate }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw ClientError.connectionUnavailable }
        let response = responses.removeFirst()
        if requests.count == gate {
            await withCheckedContinuation { blocked = $0; waiting?.resume(); waiting = nil }
        }
        return try response.get()
    }
    func waitForRequest() async {
        if blocked != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func release() { blocked?.resume(); blocked = nil }
    func captured() -> [URLRequest] { requests }
}

@Suite @MainActor struct RememberedAccountTests {
    private func account(_ transport: any HTTPTransport, _ vault: TestVault, _ disk: TestJournal, _ clock: RenewalClock) throws -> ConnectedAccount {
        ConnectedAccount(client: BuddyCheckClient(configuration: try configuration(), transport: transport), vault: vault,
                         persistence: disk, uptime: { clock.uptime })
    }
    private func authorize(_ account: ConnectedAccount, _ clock: RenewalClock) async throws {
        let attempt = try account.beginAuthorization(now: clock.now, rememberSession: true)
        try await account.finishAuthorization(callback: rememberedCallback(attempt), now: clock.now)
    }
    private var login: [Result<HTTPResponse, ClientError>] { [response(rememberedTokenJSON()), response(rememberedSessionJSON())] }
    private var later: Date { fixtureTime.addingTimeInterval(901) }
    private var renewed: [Result<HTTPResponse, ClientError>] {
        [response(rememberedTokenJSON(issued: later, serial: 2)), response(rememberedSessionJSON(issued: later, serial: 2))]
    }
    private func bodies(_ requests: [URLRequest]) -> [String] {
        requests.filter { $0.url?.path == "/oauth/token" }.map { String(data: $0.httpBody!, encoding: .utf8)! }
    }

    @Test func relaunchAfterAccessExpiryRenewsAndRestoresTheExactPendingCheck() async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let transport = StubTransport(login + renewed + [response(cardJSON)])
        let original = try account(transport, vault, disk, clock)
        try await authorize(original, clock)
        try original.journal?.prepare(mutation())
        let before = disk.value
        original.lock(); clock.advance(901)
        let restarted = try account(transport, vault, disk, clock)
        try await restarted.restore(now: clock.now)
        #expect(restarted.session?.sessionId == 24 && !restarted.needsSignIn)
        #expect(restarted.journal?.snapshot == before)
        _ = try await restarted.perform({ try await $0.person(42, token: $1) }, now: clock.now)
        let requests = await transport.captured()
        #expect(bodies(requests).count == 2)
        #expect(bodies(requests)[1].contains("grant_type=refresh_token"))
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access-2")
        #expect(!requests.contains { $0.url?.path.contains("/authorize") == true })
    }
    @Test func serverReportedExpiryRetriesPendingSubmissionWithoutReplacingItsIdentity() async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let issue = fixtureTime.addingTimeInterval(10)
        let transport = StubTransport(login + [response(#"{"error":{"code":"expired_session"}}"#, status: 401),
            response(rememberedTokenJSON(issued: issue, serial: 2)), response(rememberedSessionJSON(issued: issue, serial: 2)),
            response(#"{"error":{"code":"not_found"}}"#, status: 404), response(cardJSON), response(receiptJSON, status: 201)])
        let subject = try account(transport, vault, disk, clock)
        try await authorize(subject, clock)
        let operation = try mutation()
        let journal = try #require(subject.journal)
        try journal.prepare(operation)
        clock.advance(10)
        let receipt = try await subject.perform({ try await journal.reconcile(client: $0, token: $1) }, now: clock.now)
        #expect(receipt.operationId == operation.id && subject.journal === journal)
        let requests = await transport.captured()
        let writes = requests.filter { $0.httpMethod == "POST" && $0.url?.path != "/oauth/token" }
        #expect(writes.count == 1 && writes.first?.httpBody == operation.body)
        #expect(requests.filter { $0.url?.path.contains("/receipts/") == true }.count == 2)
        #expect(journal.snapshot.pending == nil)
    }
    @Test func lostRenewalResponseRecoversAfterRestartUsingTheSameCredentialAndExchangeID() async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let transport = StubTransport(login + [.failure(.connectionUnavailable)] + renewed)
        let first = try account(transport, vault, disk, clock)
        try await authorize(first, clock)
        try first.journal?.prepare(mutation())
        first.lock(); clock.advance(901)
        await #expect(throws: ClientError.connectionUnavailable) { try await first.restore(now: clock.now) }
        #expect(disk.value?.pending?.id == operationID)
        clock.advance(10)
        let restarted = try account(transport, vault, disk, clock)
        try await restarted.restore(now: clock.now)
        #expect(restarted.session?.sessionId == 24)
        let exchanges = bodies(await transport.captured())
        #expect(exchanges.count == 3 && exchanges[1] == exchanges[2])
    }
    @Test(arguments: ["late", "wall_forward", "wall_backward", "reboot"])
    func uncertainRecoveryRequiresHumanSignInWithoutReplayingOrLosingDraft(_ scenario: String) async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let transport = StubTransport(login + [.failure(.connectionUnavailable)])
        let first = try account(transport, vault, disk, clock)
        try await authorize(first, clock); try first.journal?.prepare(mutation())
        first.lock(); clock.advance(901)
        await #expect(throws: ClientError.connectionUnavailable) { try await first.restore(now: clock.now) }
        switch scenario {
        case "late": clock.advance(121)
        case "wall_forward": clock.now.addTimeInterval(40)
        case "wall_backward": clock.now.addTimeInterval(-10)
        default: clock.advance(10); clock.uptime = 5
        }
        let restarted = try account(transport, vault, disk, clock)
        await #expect(throws: ClientError.signInRequired) { try await restarted.restore(now: clock.now) }
        #expect(restarted.session == nil && restarted.needsSignIn)
        #expect(disk.value?.pending?.id == operationID && !vault.values.isEmpty)
        #expect(await transport.captured().count == 3)
    }
    @Test func initialExchangeResponseLossRecoversWithoutNewConsent() async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let transport = StubTransport([.failure(.connectionUnavailable)] + login)
        let first = try account(transport, vault, disk, clock)
        await #expect(throws: ClientError.connectionUnavailable) { try await authorize(first, clock) }
        try first.cancelAuthorization() // The browser adapter's error cleanup.
        clock.advance(10)
        let restarted = try account(transport, vault, disk, clock)
        try await restarted.restore(now: clock.now)
        #expect(restarted.session?.rememberedSessionId == rememberedFamily)
        #expect(bodies(await transport.captured())[0] == bodies(await transport.captured())[1])
        #expect(vault.values["connected.authorization.exchange"] == nil)
    }
    @Test func tokenIsStoredBeforeTheFollowingSessionRequestCanFail() async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let transport = StubTransport([response(rememberedTokenJSON()), .failure(.connectionUnavailable), response(rememberedSessionJSON())])
        let first = try account(transport, vault, disk, clock)
        await #expect(throws: ClientError.connectionUnavailable) { try await authorize(first, clock) }
        let restarted = try account(transport, vault, disk, clock)
        try await restarted.restore(now: clock.now)
        #expect(restarted.session != nil && !restarted.needsSignIn)
        #expect(bodies(await transport.captured()).count == 1)
    }
    @Test func simultaneousForegroundRestoresShareOneRenewal() async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let transport = GatedAuthTransport(login + renewed + [response(rememberedSessionJSON(issued: later, serial: 2))], gate: 3)
        let subject = try account(transport, vault, disk, clock)
        try await authorize(subject, clock); subject.lock(); clock.advance(901)
        let first = Task { try await subject.restore(now: clock.now) }
        await transport.waitForRequest()
        let second = Task { try await subject.restore(now: clock.now) }
        await Task.yield()
        await transport.release()
        try await first.value; try await second.value
        #expect(bodies(await transport.captured()).count == 2)
        #expect(subject.session?.sessionId == 24)
    }
    @Test func backgroundDuringRenewalSavesRotatedPairWithoutRestoringVisibleData() async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let transport = GatedAuthTransport(login + renewed + [response(rememberedSessionJSON(issued: later, serial: 2))], gate: 3)
        let subject = try account(transport, vault, disk, clock)
        try await authorize(subject, clock); try subject.journal?.prepare(mutation()); subject.lock(); clock.advance(901)
        let work = Task { try await subject.restore(now: clock.now) }
        await transport.waitForRequest(); subject.lock(); await transport.release()
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(subject.session == nil && subject.journal == nil)
        let restarted = try account(transport, vault, disk, clock)
        try await restarted.restore(now: clock.now)
        #expect(restarted.session?.sessionId == 24 && restarted.journal?.snapshot.pending?.id == operationID)
        #expect(bodies(await transport.captured()).count == 2)
    }
    @Test func signOutDuringRenewalCannotResurrectAccountAndRevokesLateCredential() async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let transport = GatedAuthTransport(login + [response(rememberedTokenJSON(issued: later, serial: 2)), response("{}"), response("{}")], gate: 3)
        let subject = try account(transport, vault, disk, clock)
        try await authorize(subject, clock); try subject.journal?.prepare(mutation()); subject.lock(); clock.advance(901)
        let work = Task { try await subject.restore(now: clock.now) }
        await transport.waitForRequest()
        #expect(try await subject.signOut())
        await transport.release()
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(subject.session == nil && !subject.hasStoredAccount && vault.values.isEmpty && disk.value == nil)
        let revocations = await transport.captured().filter { $0.url?.path == "/oauth/revoke" }
        #expect(revocations.count == 2)
        #expect(String(data: revocations.last!.httpBody!, encoding: .utf8)!.contains("token=synthetic-refresh-2"))
    }
    @Test func failedRotatedCredentialSaveKeepsRecoverableInputOnDisk() async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let transport = GatedAuthTransport(login + [response(rememberedTokenJSON(issued: later, serial: 2))] + renewed, gate: 3)
        let subject = try account(transport, vault, disk, clock)
        try await authorize(subject, clock); try subject.journal?.prepare(mutation()); subject.lock(); clock.advance(901)
        let work = Task { try await subject.restore(now: clock.now) }
        await transport.waitForRequest(); vault.failWrites = true; await transport.release()
        await #expect(throws: ClientError.journalUnavailable) { try await work.value }
        vault.failWrites = false; clock.advance(10)
        let restarted = try account(transport, vault, disk, clock)
        try await restarted.restore(now: clock.now)
        let exchanges = bodies(await transport.captured())
        #expect(exchanges[1] == exchanges[2])
        #expect(restarted.journal?.snapshot.pending?.id == operationID)
    }
    @Test(arguments: ["account_unavailable", "revoked_session", "refresh_reuse_detected", "remembered_session_expired", "unavailable"])
    func renewalFailuresDistinguishRevocationFromExpiryAndServiceFailure(_ code: String) async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let transport = StubTransport(login + [response("{\"error\":\"invalid_grant\",\"error_code\":\"\(code)\"}", status: 400)])
        let subject = try account(transport, vault, disk, clock)
        try await authorize(subject, clock); try subject.journal?.prepare(mutation()); subject.lock(); clock.advance(901)
        await #expect(throws: ClientError.server(status: 400, code: code)) { try await subject.restore(now: clock.now) }
        let revoked = ["account_unavailable", "revoked_session", "refresh_reuse_detected"].contains(code)
        #expect((disk.value == nil && vault.values.isEmpty) == revoked)
        #expect(subject.session == nil && subject.journal == nil)
        if !revoked { #expect(disk.value?.pending?.id == operationID) }
    }

    @Test func invalidRenewedSessionCannotBeBypassedByTryingTheActionAgain() async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let wrong = rememberedSessionJSON(issued: later, serial: 2)
            .replacingOccurrences(of: rememberedFamily.uuidString.lowercased(), with: UUID().uuidString.lowercased())
        let transport = StubTransport(login + [response(rememberedTokenJSON(issued: later, serial: 2)), response(wrong), response(wrong)])
        let subject = try account(transport, vault, disk, clock)
        try await authorize(subject, clock); try subject.journal?.prepare(mutation()); clock.advance(901)
        for _ in 0..<2 {
            await #expect(throws: ClientError.invalidResponse) {
                try await subject.perform({ try await $0.person(42, token: $1) }, now: clock.now)
            }
        }
        #expect(!((await transport.captured()).contains { $0.url?.path.hasSuffix("/people/42") == true }))
        #expect(disk.value?.pending?.id == operationID)
    }

    @Test func accessLossOnRememberedAccountPurgesBeforeAnyRenewal() async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let transport = StubTransport(login + [response(#"{"error":{"code":"account_unavailable"}}"#, status: 401)])
        let subject = try account(transport, vault, disk, clock)
        try await authorize(subject, clock); try subject.journal?.prepare(mutation()); clock.advance(1)
        await #expect(throws: ClientError.server(status: 401, code: "account_unavailable")) {
            try await subject.perform({ try await $0.person(42, token: $1) }, now: clock.now)
        }
        #expect(vault.values.isEmpty && disk.value == nil && subject.session == nil)
        #expect(bodies(await transport.captured()).count == 1)
    }

    @Test func repeatedServerExpiryDoesNotCauseAnUnlimitedRefreshLoop() async throws {
        let vault = TestVault(), disk = TestJournal(), clock = RenewalClock()
        let expiry = response(#"{"error":{"code":"expired_session"}}"#, status: 401)
        let transport = StubTransport(login + [expiry] + renewed + [expiry])
        let subject = try account(transport, vault, disk, clock)
        try await authorize(subject, clock); try subject.journal?.prepare(mutation())
        await #expect(throws: ClientError.server(status: 401, code: "expired_session")) {
            try await subject.perform({ try await $0.person(42, token: $1) }, now: clock.now)
        }
        #expect(subject.session == nil && subject.needsSignIn)
        let exchanges = bodies(await transport.captured())
        #expect(disk.value?.pending?.id == operationID && exchanges.count == 2)
    }
}

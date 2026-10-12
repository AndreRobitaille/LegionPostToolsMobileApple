import Foundation
import Testing
@testable import BuddyCheckAPI

@Suite @MainActor struct AccountTests {
    private var tokenResponse: Result<HTTPResponse, ClientError> {
        response("{\"access_token\":\"synthetic-token\",\"token_type\":\"Bearer\",\"expires_in\":900,\"scope\":\"buddy_check\",\"created_at\":1792000000}")
    }
    private func authorize(_ account: ConnectedAccount) async throws {
        let attempt = try account.beginAuthorization(now: fixtureTime)
        let callback = URL(string: attempt.configuration.redirectURI.absoluteString + "?code=test&state=" + attempt.state)!
        try await account.finishAuthorization(callback: callback, now: fixtureTime)
    }
    @Test func ordinaryExpiryRetainsJournalAndReauthorizationRecoversSameAccount() async throws {
        let vault = TestVault(); let disk = TestJournal()
        let transport = StubTransport([tokenResponse, response(sessionJSON), tokenResponse, response(sessionJSON)])
        let account = ConnectedAccount(client: BuddyCheckClient(configuration: try configuration(), transport: transport), vault: vault, persistence: disk)
        try await authorize(account)
        try account.journal?.prepare(mutation())
        account.lock()
        try await account.restore(now: fixtureTime.addingTimeInterval(901))
        #expect(account.session == nil && account.needsSignIn)
        #expect(disk.value?.pending?.id == operationID)
        #expect(!vault.values.isEmpty)
        try await authorize(account)
        #expect(account.journal?.snapshot.pending?.id == operationID)
    }
    @Test func differentHumanCannotAcquireExistingDraft() async throws {
        let vault = TestVault(); let disk = TestJournal()
        let otherSession = sessionJSON.replacingOccurrences(of: #""id":7"#, with: #""id":8"#)
        let transport = StubTransport([tokenResponse, response(sessionJSON), tokenResponse, response(otherSession), response("{}")])
        let account = ConnectedAccount(client: BuddyCheckClient(configuration: try configuration(), transport: transport), vault: vault, persistence: disk)
        try await authorize(account)
        try account.journal?.prepare(mutation())
        account.lock()
        await #expect(throws: ClientError.accountMismatch) { try await authorize(account) }
        #expect(account.session == nil)
        #expect(disk.value?.scope.userID == 7 && disk.value?.pending?.id == operationID)
        #expect(await transport.captured().last?.url?.path == "/oauth/revoke")
    }
    @Test(arguments: ["expired_session", "invalid_session", "revoked_session", "account_unavailable"])
    func sessionErrorsPurgeOnlyConfirmedRevocation(_ code: String) async throws {
        let vault = TestVault(); let disk = TestJournal()
        let transport = StubTransport([tokenResponse, response(sessionJSON), response("{\"error\":{\"code\":\"\(code)\"}}", status: 401)])
        let account = ConnectedAccount(client: BuddyCheckClient(configuration: try configuration(), transport: transport), vault: vault, persistence: disk)
        try await authorize(account)
        try account.journal?.prepare(mutation())
        account.lock()
        await #expect(throws: ClientError.server(status: 401, code: code)) { try await account.restore(now: fixtureTime) }
        if ["revoked_session", "account_unavailable"].contains(code) {
            #expect(disk.value == nil && vault.values.isEmpty)
        } else { #expect(disk.value?.pending?.id == operationID && !vault.values.isEmpty) }
        #expect(account.session == nil && account.journal == nil)
    }
    @Test func explicitSignOutPurgesLocallyEvenWhenRemoteRevocationFails() async throws {
        let vault = TestVault(); let disk = TestJournal()
        let transport = StubTransport([tokenResponse, response(sessionJSON), .failure(.connectionUnavailable)])
        let account = ConnectedAccount(client: BuddyCheckClient(configuration: try configuration(), transport: transport), vault: vault, persistence: disk)
        try await authorize(account)
        try account.journal?.prepare(mutation())
        #expect(try await account.signOut() == false)
        #expect(account.session == nil && account.journal == nil && disk.value == nil && vault.values.isEmpty)
    }
    @Test(arguments: [401, 403])
    func websiteAccessLossStopsEvenAnUnexpiredMobileSession(_ status: Int) async throws {
        let vault = TestVault(), disk = TestJournal()
        let transport = StubTransport([tokenResponse, response(sessionJSON),
                                       response(#"{"error":{"code":"account_unavailable"}}"#, status: status)])
        let account = ConnectedAccount(client: BuddyCheckClient(configuration: try configuration(), transport: transport),
                                       vault: vault, persistence: disk)
        try await authorize(account)
        try account.journal?.prepare(mutation())
        #expect(account.session != nil && !account.needsSignIn)
        // Only one second has passed: access loss must not wait for token expiry.
        await #expect(throws: ClientError.server(status: status, code: "account_unavailable")) {
            try await account.perform({ client, token in try await client.person(42, token: token) },
                                      now: fixtureTime.addingTimeInterval(1))
        }
        #expect(account.needsSignIn && !account.hasStoredAccount)
        #expect(account.session == nil && account.journal == nil)
        #expect(disk.value == nil && vault.values.isEmpty)
        let requests = await transport.captured()
        #expect(requests.last?.httpMethod == "GET")
        #expect(requests.filter { $0.httpMethod == "POST" }.count == 1) // Human authorization only.
    }
    @Test func recordPermissionDenialDoesNotBecomeAccountRevocation() async throws {
        let vault = TestVault(), disk = TestJournal()
        let transport = StubTransport([tokenResponse, response(sessionJSON),
                                       response(#"{"error":{"code":"not_permitted"}}"#, status: 403)])
        let account = ConnectedAccount(client: BuddyCheckClient(configuration: try configuration(), transport: transport),
                                       vault: vault, persistence: disk)
        try await authorize(account)
        try account.journal?.prepare(mutation())
        let before = disk.value
        await #expect(throws: ClientError.server(status: 403, code: "not_permitted")) {
            try await account.perform({ client, token in try await client.person(42, token: token) }, now: fixtureTime)
        }
        #expect(account.session != nil && !account.needsSignIn && account.hasStoredAccount)
        #expect(disk.value == before && !vault.values.isEmpty)
    }
}

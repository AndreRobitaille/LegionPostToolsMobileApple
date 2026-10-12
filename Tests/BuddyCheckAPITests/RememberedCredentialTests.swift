import Foundation
import Testing
@testable import BuddyCheckAPI

let rememberedFamily = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
func rememberedTokenJSON(authorized: Date = fixtureTime, issued: Date = fixtureTime, serial: Int = 1) -> String {
    let formatter = ISO8601DateFormatter()
    return """
    {"access_token":"synthetic-access-\(serial)","token_type":"Bearer","expires_in":900,"scope":"buddy_check",
    "created_at":\(Int(issued.timeIntervalSince1970)),"refresh_token":"synthetic-refresh-\(serial)",
    "issuer":"https://post.example.test","installation_id":1,"user_id":7,"session_id":\(22 + serial),
    "remembered_session_id":"\(rememberedFamily.uuidString.lowercased())",
    "authorized_at":"\(formatter.string(from: authorized))","remembered_until":"\(formatter.string(from: authorized.addingTimeInterval(180 * 86400)))",
    "expires_at":"\(formatter.string(from: issued.addingTimeInterval(900)))"}
    """
}
func rememberedSessionJSON(authorized: Date = fixtureTime, issued: Date = fixtureTime, serial: Int = 1) -> String {
    let formatter = ISO8601DateFormatter()
    return """
    {"installation":{"id":1,"issuer":"https://post.example.test","name":"Synthetic Post","timezone":"America/Chicago"},
    "user":{"id":7,"name":"Jamie Example"},"session_id":\(22 + serial),"expires_at":"\(formatter.string(from: issued.addingTimeInterval(900)))",
    "remembered_session_id":"\(rememberedFamily.uuidString.lowercased())",
    "authorized_at":"\(formatter.string(from: authorized))","remembered_until":"\(formatter.string(from: authorized.addingTimeInterval(180 * 86400)))",
    "capabilities":{"buddy_checks":true,"contacts_export":false,"refresh":true}}
    """
}
func rememberedCallback(_ attempt: AuthorizationAttempt) -> URL {
    URL(string: attempt.configuration.redirectURI.absoluteString + "?code=synthetic-code&state=" + attempt.state)!
}

@Suite struct RememberedCredentialTests {
    @Test func optInIsExplicitAndBothExchangesHaveStableOperationIdentities() async throws {
        let config = try configuration()
        let attempt = try AuthorizationAttempt(configuration: config, now: fixtureTime, rememberSession: true)
        let query = URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains(URLQueryItem(name: "remember_session", value: "180_days")) == true)
        let original = try JSONEncoder().encode(attempt)
        #expect(try JSONDecoder().decode(AuthorizationAttempt.self, from: original).exchangeId == attempt.exchangeId)
        let later = fixtureTime.addingTimeInterval(901)
        let transport = StubTransport([response(rememberedTokenJSON()), response(rememberedTokenJSON(issued: later, serial: 2))])
        let client = BuddyCheckClient(configuration: config, transport: transport)
        let first = try await client.exchange(rememberedCallback(attempt), attempt: attempt, now: fixtureTime)
        let exchangeID = UUID()
        let second = try await client.renew(first, exchangeID: exchangeID, now: later)
        #expect(second.rememberedUntil == first.rememberedUntil && second.authorizedAt == first.authorizedAt)
        #expect(second.rememberedSessionId == first.rememberedSessionId && second.sessionId != first.sessionId)
        let requests = await transport.captured()
        let firstBody = String(data: try #require(requests[0].httpBody), encoding: .utf8)!
        let secondBody = String(data: try #require(requests[1].httpBody), encoding: .utf8)!
        #expect(firstBody.contains("exchange_id=" + attempt.exchangeId!.uuidString.lowercased()))
        #expect(secondBody.contains("grant_type=refresh_token") && secondBody.contains("refresh_token=synthetic-refresh-1"))
        #expect(secondBody.contains("exchange_id=" + exchangeID.uuidString.lowercased()))
        #expect(!secondBody.contains("client_secret") && !secondBody.contains("code_verifier"))
        let legacyAttempt = try AuthorizationAttempt(configuration: config)
        #expect(!legacyAttempt.authorizationURL.absoluteString.contains("remember_session"))
    }
    @Test(arguments: ["issuer", "human", "installation", "family", "deadline", "same_tokens", "long_access"])
    func renewalRejectsChangedAuthorityOrExtendedLifetime(_ scenario: String) async throws {
        let attempt = try AuthorizationAttempt(configuration: configuration(), now: fixtureTime, rememberSession: true)
        let later = fixtureTime.addingTimeInterval(901)
        var json = rememberedTokenJSON(issued: later, serial: 2)
        switch scenario {
        case "issuer": json = json.replacingOccurrences(of: "https://post.example.test", with: "https://other.example.test")
        case "human": json = json.replacingOccurrences(of: #""user_id":7"#, with: #""user_id":8"#)
        case "installation": json = json.replacingOccurrences(of: #""installation_id":1"#, with: #""installation_id":2"#)
        case "family": json = json.replacingOccurrences(of: rememberedFamily.uuidString.lowercased(), with: UUID().uuidString)
        case "deadline": json = rememberedTokenJSON(authorized: fixtureTime.addingTimeInterval(60), issued: later, serial: 2)
        case "same_tokens": json = rememberedTokenJSON(issued: later, serial: 1)
        default: json = json.replacingOccurrences(of: #""expires_in":900"#, with: #""expires_in":15552000"#)
        }
        let transport = StubTransport([response(rememberedTokenJSON()), response(json)])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        let first = try await client.exchange(rememberedCallback(attempt), attempt: attempt, now: fixtureTime)
        await #expect(throws: ClientError.invalidResponse) { try await client.renew(first, exchangeID: UUID(), now: later) }
    }
    @Test func serverClockAlignmentSurvivesKeychainEncodingWithoutExtendingAccess() async throws {
        let deviceNow = fixtureTime.addingTimeInterval(83)
        let attempt = try AuthorizationAttempt(configuration: configuration(), now: deviceNow, rememberSession: true)
        let transport = StubTransport([.success(HTTPResponse(data: Data(rememberedTokenJSON().utf8), status: 200,
                                                          serverDate: fixtureTime, requestStartedAt: deviceNow))])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        let credential = try await client.exchange(rememberedCallback(attempt), attempt: attempt, now: deviceNow)
        let saved = try JSONEncoder().encode(credential)
        let restored = try JSONDecoder().decode(AccessCredential.self, from: saved)
        #expect(restored.isValid(at: deviceNow.addingTimeInterval(898)))
        #expect(!restored.isValid(at: deviceNow.addingTimeInterval(899)))
        #expect(restored.serverExpiresAt == fixtureTime.addingTimeInterval(900))
        #expect(restored.rememberedUntil == fixtureTime.addingTimeInterval(180 * 86400))
    }
    @Test(arguments: ["account_unavailable", "revoked_session", "refresh_reuse_detected", "remembered_session_expired", "invalid_refresh_token", "unavailable"])
    func tokenErrorsRetainSpecificRevocationMeaning(_ code: String) async throws {
        let attempt = try AuthorizationAttempt(configuration: configuration(), now: fixtureTime, rememberSession: true)
        let transport = StubTransport([response("{\"error\":\"invalid_grant\",\"error_code\":\"\(code)\"}", status: 400)])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        await #expect(throws: ClientError.server(status: 400, code: code)) {
            try await client.exchange(rememberedCallback(attempt), attempt: attempt, now: fixtureTime)
        }
        #expect(ClientError.server(status: 400, code: code).confirmsRevocation ==
                ["account_unavailable", "revoked_session", "refresh_reuse_detected"].contains(code))
    }

    @Test func recoveredResponseReportsRemainingLifetimeWithoutMovingOriginalExpiry() async throws {
        let attempt = try AuthorizationAttempt(configuration: configuration(), now: fixtureTime, rememberSession: true)
        let recovery = fixtureTime.addingTimeInterval(30)
        let json = rememberedTokenJSON().replacingOccurrences(of: #""expires_in":900"#, with: #""expires_in":870"#)
        let transport = StubTransport([.success(HTTPResponse(data: Data(json.utf8), status: 200,
                                                           serverDate: recovery, requestStartedAt: recovery))])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        let result = try await client.exchange(rememberedCallback(attempt), attempt: attempt, now: recovery)
        #expect(result.expiresIn == 870 && result.createdAt == Int(fixtureTime.timeIntervalSince1970))
        #expect(result.serverExpiresAt == fixtureTime.addingTimeInterval(900))
        #expect(result.isValid(at: fixtureTime.addingTimeInterval(898)))
        #expect(!result.isValid(at: fixtureTime.addingTimeInterval(899)))
    }
}

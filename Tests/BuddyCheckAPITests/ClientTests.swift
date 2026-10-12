import Foundation
import Testing
@testable import BuddyCheckAPI

actor StubTransport: HTTPTransport {
    var responses: [Result<HTTPResponse, ClientError>]
    var requests: [URLRequest] = []
    init(_ responses: [Result<HTTPResponse, ClientError>]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw ClientError.connectionUnavailable }
        return try responses.removeFirst().get()
    }
    func captured() -> [URLRequest] { requests }
}

let fixtureTime = Date(timeIntervalSince1970: 1_792_000_000)
let operationID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
func configuration() throws -> ConnectionConfiguration {
    try ConnectionConfiguration(issuer: URL(string: "https://post.example.test")!, clientID: "public-client",
                                redirectURI: URL(string: "org.wipost165.buddychecks:/oauth/callback")!)
}
func response(_ body: String, status: Int = 200) -> Result<HTTPResponse, ClientError> {
    .success(HTTPResponse(data: Data(body.utf8), status: status))
}
let sessionJSON = """
{"installation":{"id":1,"issuer":"https://post.example.test","name":"Synthetic Post","timezone":"America/Chicago"},
"user":{"id":7,"name":"Jamie Example"},"session_id":23,"expires_at":"2026-10-11T20:45:00.000000Z",
"capabilities":{"buddy_checks":true,"contacts_export":false,"refresh":false}}
"""
let coverageJSON = """
{"contact_history":"partial","missing_history":"unknown","attendance":"explicit_registers_only","checked_at":"2026-10-11T20:30:00.000000Z"}
"""
let cardJSON = """
{"id":42,"first_name":"Alex","last_name":"Example","phone":null,"email":null,"assignment_ids":[],"export_available":false,
"eligibility":{"eligible":false,"reason":"recent_attempt","checked_at":"2026-10-11T20:30:00.000000Z","expires_at":"2026-10-11T20:31:00.000000Z"},"coverage":\(coverageJSON)}
"""
let contactJSON = """
{"id":81,"source_id":81,"person_id":42,"revision":1,"channel":"phone","outcome":"no_answer","precision":"instant",
"occurred_at":"2026-10-11T20:30:00.000000Z","occurred_on":"2026-10-11","entry_zone":"America/Chicago","membership_year":2026,
"notes":"Synthetic attempt","legacy_follow_up_on":null,"recorded_at":"2026-10-11T20:31:00.000000Z"}
"""
let receiptJSON = """
{"operation_id":"11111111-1111-4111-8111-111111111111","accepted_at":"2026-10-11T20:31:00.000000Z","state":"accepted","contact":\(contactJSON),"follow_up":null}
"""
func mutation() throws -> PendingMutation {
    try .record(personID: 42, facts: CheckFacts(channel: .phone, outcome: .noAnswer, occurredAt: fixtureTime,
                                               entryZone: "America/Chicago", notes: "Synthetic attempt"), operationID: operationID, now: fixtureTime)
}

@Suite struct ClientTests {
    @Test func randomSuggestionsRemainSeparateFromRankedHistoryAndTolerateOlderServer() async throws {
        let json = """
        {"state":"insufficient_history","coverage":\(coverageJSON),"random_candidates":[
        {"id":42,"first_name":"Alex","last_name":"Example"},
        {"id":43,"first_name":"Taylor","last_name":"Example"},
        {"id":44,"first_name":"Morgan","last_name":"Example"}]}
        """
        let transport = StubTransport([response(json), response("{\"state\":\"insufficient_history\",\"coverage\":\(coverageJSON)}")])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        let suggestion = try await client.suggestion(excluding: [45], token: "synthetic")
        #expect(suggestion.state == .insufficientHistory && suggestion.reason == nil && suggestion.person == nil)
        #expect(suggestion.randomCandidates?.map(\.id) == [42, 43, 44])
        #expect(try await client.suggestion(token: "synthetic").randomCandidates == nil)
        let requests = await transport.captured()
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
        let query = URLComponents(url: try #require(requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains(URLQueryItem(name: "exclude_ids[]", value: "45")) == true)
    }
    @Test(arguments: ["too_many", "duplicate", "excluded", "invalid_id", "wrong_state"])
    func rejectsInvalidRandomSuggestionResponses(_ scenario: String) async throws {
        let ids = scenario == "too_many" ? [42, 43, 44, 45] : scenario == "duplicate" ? [42, 42] : scenario == "invalid_id" ? [0] : [42]
        let people = ids.map { "{\"id\":\($0),\"first_name\":\"Alex\",\"last_name\":\"Example\"}" }.joined(separator: ",")
        let state = scenario == "wrong_state" ? "exhausted" : "insufficient_history"
        let transport = StubTransport([response("{\"state\":\"\(state)\",\"coverage\":\(coverageJSON),\"random_candidates\":[\(people)]}")])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        await #expect(throws: ClientError.invalidResponse) {
            try await client.suggestion(excluding: scenario == "excluded" ? [42] : [], token: "synthetic")
        }
    }
    @Test func eligibilityClockAlignmentKeepsOriginalWireTimesAndExpiresConservatively() async throws {
        let serverNow = try #require(ISO8601DateFormatter().date(from: "2026-10-11T20:30:00Z"))
        let deviceNow = serverNow.addingTimeInterval(83)
        let json = cardJSON.replacingOccurrences(of: #""eligible":false"#, with: #""eligible":true"#)
            .replacingOccurrences(of: #""reason":"recent_attempt""#, with: #""reason":null"#)
        let transport = StubTransport([.success(HTTPResponse(data: Data(json.utf8), status: 200, serverDate: serverNow, requestStartedAt: deviceNow))])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        let card = try await client.person(42, token: "synthetic")
        #expect(card.eligibility.checkedAt == serverNow)
        #expect(card.eligibility.expiresAt == serverNow.addingTimeInterval(60))
        #expect(card.eligibility.permitsHandoff(at: deviceNow.addingTimeInterval(58)))
        #expect(!card.eligibility.permitsHandoff(at: deviceNow.addingTimeInterval(59)))
        let encoded = try WireJSON.encoder().encode(card.eligibility)
        let raw = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(raw.keys) == ["eligible", "checked_at", "expires_at"])
        let withoutRuntimeClock = try WireJSON.decoder().decode(Eligibility.self, from: encoded)
        #expect(!withoutRuntimeClock.permitsHandoff(at: deviceNow))
    }
    @Test func contactExportUsesPeopleRouteAndValidatesIdentity() async throws {
        // Matches GET /api/mobile/v1/people/:id/contact-export, including the
        // ordinary caller's intentionally empty address.
        let json = #"{"person_id":42,"source":"legion_post_tools/person/42","version":"current-projection","fields":{"first_name":"Alex","last_name":"Example","company":"American Legion Post 165","phone":null,"email":"alex@example.test","address":{}},"permitted_fields":["first_name","last_name","company","email"],"address_coverage":"not_permitted","checked_at":"2026-10-11T20:30:00Z"}"#
        let transport = StubTransport([response(json), response(json.replacingOccurrences(of: #""person_id":42"#, with: #""person_id":43"#))])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        let projection = try await client.contactExport(personID: 42, token: "synthetic-token")
        let copy = try PermittedContactCopy(projection)
        #expect(copy.company == "American Legion Post 165")
        #expect(copy.email == "alex@example.test" && copy.address == nil)
        let request = try #require(await transport.captured().first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/mobile/v1/people/42/contact-export")
        await #expect(throws: ClientError.invalidResponse) {
            try await client.contactExport(personID: 42, token: "synthetic-token")
        }
    }
    @Test func decodesSourceSessionUserAndRejectsDifferentIssuer() async throws {
        let transport = StubTransport([response(sessionJSON), response(sessionJSON.replacingOccurrences(of: "post.example.test", with: "other.example.test"))])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        let session = try await client.session(token: "synthetic-token")
        #expect(session.user.id == 7)
        #expect(session.sessionId == 23)
        #expect(!session.capabilities.refresh)
        await #expect(throws: ClientError.invalidResponse) { try await client.session(token: "synthetic-token") }
        let request = try #require(await transport.captured().first)
        #expect(request.url?.path == "/api/mobile/v1/session")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
    }
    @Test func boundsSearchAndEncodesQueryAndPagination() async throws {
        let transport = StubTransport([response(#"{"items":[{"id":42,"first_name":"Alex","last_name":"Example"}],"next_cursor":"42"}"#)])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        await #expect(throws: ClientError.invalidInput) { try await client.people(query: "A", token: "t") }
        await #expect(throws: ClientError.invalidInput) { try await client.people(query: "Alex", limit: 51, token: "t") }
        await #expect(throws: ClientError.invalidInput) { try await client.history(cursor: "../x", token: "t") }
        let page = try await client.people(query: " A&B + ", cursor: "12", limit: 50, token: "t")
        #expect(page.items.first?.name == "Alex Example")
        #expect(page.nextCursor == "42")
        let requests = await transport.captured()
        #expect(requests.count == 1)
        let items = URLComponents(url: try #require(requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first(where: { $0.name == "q" })?.value == "A&B +")
        #expect(items?.first(where: { $0.name == "cursor" })?.value == "12")
        #expect(requests.first?.url?.query?.contains("%2B") == true)
    }
    @Test func preservesUnknownCoverageAndUnavailableIsNotExhausted() async throws {
        let transport = StubTransport([
            response("{\"state\":\"insufficient_history\",\"coverage\":\(coverageJSON)}"),
            response(#"{"error":{"code":"unavailable"}}"#, status: 503)
        ])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        let suggestion = try await client.suggestion(token: "t")
        #expect(suggestion.state == .insufficientHistory && suggestion.person == nil)
        #expect(suggestion.coverage.missingHistory == "unknown")
        await #expect(throws: ClientError.server(status: 503, code: "unavailable")) { try await client.suggestion(token: "t") }
    }
    @Test func pendingBodyAndOperationIDRemainByteIdentical() async throws {
        let operation = try mutation()
        let transport = StubTransport([response(receiptJSON, status: 201), response(receiptJSON, status: 201)])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        _ = try await client.submit(operation, token: "first-session")
        let restored = try JSONDecoder().decode(PendingMutation.self, from: JSONEncoder().encode(operation))
        _ = try await client.submit(restored, token: "renewed-session")
        let requests = await transport.captured()
        #expect(requests.map(\.httpBody) == [operation.body, operation.body])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") == nil })
        let body = try #require(JSONSerialization.jsonObject(with: operation.body) as? [String: Any])
        #expect(body["operation_id"] as? String == operationID.uuidString)
        #expect(body["person_id"] as? Int == 42)
        #expect(body["actor_id"] == nil && body["assignment_id"] == nil)
        #expect((body["facts"] as? [String: Any])?["outcome"] as? String == "no_answer")
    }
    @Test func rejectsWrongReceiptAndKeepsErrorDistinctions() async throws {
        let transport = StubTransport([
            response(receiptJSON.replacingOccurrences(of: "11111111-1111-4111-8111-111111111111", with: UUID().uuidString), status: 201),
            response(#"{"error":{"code":"invalid_session"}}"#, status: 401),
            response(#"{"error":{"code":"revoked_session"}}"#, status: 401)
        ])
        let client = BuddyCheckClient(configuration: try configuration(), transport: transport)
        await #expect(throws: ClientError.invalidResponse) { try await client.submit(mutation(), token: "t") }
        await #expect(throws: ClientError.server(status: 401, code: "invalid_session")) { try await client.session(token: "t") }
        await #expect(throws: ClientError.server(status: 401, code: "revoked_session")) { try await client.session(token: "t") }
        #expect(!ClientError.server(status: 401, code: "invalid_session").confirmsRevocation)
        #expect(ClientError.server(status: 401, code: "revoked_session").confirmsRevocation)
    }
    @Test func legacyDatesNeverBecomeInventedMidnight() throws {
        let json = contactJSON.replacingOccurrences(of: #""precision":"instant""#, with: #""precision":"date""#)
            .replacingOccurrences(of: #""occurred_at":"2026-10-11T20:30:00.000000Z""#, with: #""occurred_at":null"#)
            .replacingOccurrences(of: #""entry_zone":"America/Chicago""#, with: #""entry_zone":null"#)
        let legacy = try WireJSON.decoder().decode(ContactRecord.self, from: Data(json.utf8))
        #expect(legacy.occurredAt == nil)
        let facts = try CheckFacts(correcting: legacy, channel: .phone, outcome: .reached)
        let operation = try PendingMutation.correct(legacy, facts: facts)
        let body = try #require(JSONSerialization.jsonObject(with: operation.body) as? [String: Any])
        let encoded = try #require(body["facts"] as? [String: Any])
        #expect(encoded["occurred_on"] as? String == "2026-10-11")
        #expect(encoded["occurred_at"] == nil && encoded["entry_zone"] == nil)
        #expect(body["expected_revision"] as? Int == 1)
    }
    @Test func expiredEligibilityNeverPermitsHandoff() throws {
        let card = try WireJSON.decoder().decode(PersonCardResponse.self, from: Data(cardJSON.utf8))
        #expect(!card.eligibility.permitsHandoff(at: card.eligibility.checkedAt))
        let eligible = try WireJSON.decoder().decode(PersonCardResponse.self, from: Data(cardJSON
            .replacingOccurrences(of: #""eligible":false"#, with: #""eligible":true"#)
            .replacingOccurrences(of: #""reason":"recent_attempt""#, with: #""reason":null"#).utf8))
        #expect(eligible.eligibility.permitsHandoff(at: eligible.eligibility.checkedAt))
        #expect(!eligible.eligibility.permitsHandoff(at: eligible.eligibility.expiresAt))
    }
}

@Suite struct AuthorizationTests {
    @Test func rejectsUnsafeIssuerConfigurations() throws {
        for value in ["http://post.example.test", "https://name:secret@post.example.test", "https://post.example.test/api", "https://post.example.test?secret=1", "https://post.example.test#fragment"] {
            #expect(throws: ClientError.invalidConfiguration) {
                try ConnectionConfiguration(issuer: URL(string: value)!, clientID: "client", redirectURI: configuration().redirectURI)
            }
        }
    }
    @Test func PKCEMatchesPublishedS256VectorAndStateIsUnpredictable() throws {
        let attempt = AuthorizationAttempt(configuration: try configuration(), state: String(repeating: "s", count: 43),
                                           verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", startedAt: fixtureTime)
        #expect(attempt.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let a = try AuthorizationAttempt(configuration: configuration())
        let b = try AuthorizationAttempt(configuration: configuration())
        #expect(a.state.count == 43 && a.verifier.count == 43)
        #expect(a.state != b.state && a.verifier != b.verifier && a.state != a.verifier)
        #expect(!a.authorizationURL.absoluteString.contains(a.verifier))
    }
    @Test func validatesCallbackBeforeAnyNetworkRequest() async throws {
        let config = try configuration()
        let attempt = try AuthorizationAttempt(configuration: config, now: fixtureTime)
        let transport = StubTransport([])
        let client = BuddyCheckClient(configuration: config, transport: transport)
        for suffix in ["?code=a&state=wrong", "?code=a&state=\(attempt.state)&state=\(attempt.state)",
                       "?code=a&state=\(attempt.state)#fragment", "?code=a&state=\(attempt.state)&iss=https://other.example.test"] {
            let callback = URL(string: config.redirectURI.absoluteString + suffix)!
            await #expect(throws: ClientError.invalidCallback) { try await client.exchange(callback, attempt: attempt, now: fixtureTime) }
        }
        #expect(await transport.captured().isEmpty)
        #expect(throws: ClientError.invalidCallback) {
            try attempt.code(from: URL(string: "other:/oauth/callback?code=a&state=\(attempt.state)")!, currentConfiguration: config, now: fixtureTime)
        }
    }
    @Test func exchangesWithCorrectFormAndDoesNotTreatRedirectAsToken() async throws {
        let config = try configuration()
        let attempt = try AuthorizationAttempt(configuration: config, now: fixtureTime)
        let callback = URL(string: config.redirectURI.absoluteString + "?code=a%2Bb%26c&state=\(attempt.state)")!
        let transport = StubTransport([response("{\"access_token\":\"test-token\",\"token_type\":\"Bearer\",\"expires_in\":900,\"scope\":\"buddy_check\",\"created_at\":1792000000}"), response("", status: 302)])
        let client = BuddyCheckClient(configuration: config, transport: transport)
        let credential = try await client.exchange(callback, attempt: attempt, now: fixtureTime)
        #expect(!credential.isValid(at: fixtureTime.addingTimeInterval(900)))
        let request = try #require(await transport.captured().first)
        #expect(request.url?.absoluteString == "https://post.example.test/oauth/token")
        let body = String(data: try #require(request.httpBody), encoding: .utf8)!
        #expect(body.contains("code=a%2Bb%26c"))
        #expect(body.contains("code_verifier=" + attempt.verifier))
        #expect(!body.contains("client_secret") && !body.contains("refresh_token"))
        await #expect(throws: ClientError.server(status: 302, code: "unavailable")) {
            try await client.exchange(callback, attempt: attempt, now: fixtureTime)
        }
    }
}

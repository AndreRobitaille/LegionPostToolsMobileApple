import Foundation
import Testing
@testable import BuddyCheckAPI

@Suite @MainActor struct DeviceBoundaryTests {
    @Test func rejectsPhoneControlSequencesAndPreservesInternationalNumbers() throws {
        #expect(try PhoneHandoff.telephoneURL("+1 (202) 555-0100").absoluteString == "tel:+12025550100")
        for value in ["*21*5550100#", "2025550100,123", "tel:2025550100", "+1202+5550100", "123", "2025550100;ext=9"] {
            #expect(throws: ClientError.invalidInput) { try PhoneHandoff.telephoneURL(value) }
        }
    }
    @Test func phoneHandoffPersistsAnUnchosenOutcomeBeforeReturningURL() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-11T20:30:00Z"))
        let token = "{\"access_token\":\"synthetic-token\",\"token_type\":\"Bearer\",\"expires_in\":900,\"scope\":\"buddy_check\",\"created_at\":\(Int(now.timeIntervalSince1970))}"
        let card = cardJSON.replacingOccurrences(of: #""eligible":false"#, with: #""eligible":true"#)
            .replacingOccurrences(of: #""reason":"recent_attempt""#, with: #""reason":null"#)
            .replacingOccurrences(of: #""phone":null"#, with: #""phone":"+12025550100""#)
        let transport = StubTransport([response(token), response(sessionJSON), response(card)])
        let disk = TestJournal()
        let account = ConnectedAccount(client: BuddyCheckClient(configuration: try configuration(), transport: transport), vault: TestVault(), persistence: disk)
        let attempt = try account.beginAuthorization(now: now)
        try await account.finishAuthorization(callback: URL(string: attempt.configuration.redirectURI.absoluteString + "?code=test&state=" + attempt.state)!, now: now)
        let url = try await PhoneHandoff.prepare(personID: 42, account: account, now: { now })
        #expect(url.scheme == "tel")
        #expect(disk.value?.draft?.personID == 42 && disk.value?.draft?.outcome == nil)
        #expect(disk.value?.pending == nil)
        #expect(await transport.captured().filter { $0.httpMethod == "POST" }.count == 1) // OAuth only
    }
    @Test(arguments: ["contact_paused", "assigned_elsewhere", "open_follow_up", "recent_attempt", "recent_conversation",
                      "expired", "future", "no_phone", "malformed_phone", "missing", "denied", "offline"])
    func phoneHandoffRejectsCurrentAuthorityWithoutCreatingWork(_ scenario: String) async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-11T20:30:00Z"))
        var card = dialableCard
        var expected = ClientError.invalidInput
        let current: Result<HTTPResponse, ClientError>
        switch scenario {
        case "expired":
            card = card.replacingOccurrences(of: "20:31:00", with: "20:30:00")
            current = response(card)
        case "future":
            card = card.replacingOccurrences(of: "20:30:00", with: "20:30:01")
            current = response(card)
        case "no_phone":
            current = response(card.replacingOccurrences(of: #""phone":"+12025550100""#, with: #""phone":null"#))
        case "malformed_phone":
            current = response(card.replacingOccurrences(of: "+12025550100", with: "2025550100,123"))
        case "missing", "denied":
            let status = scenario == "missing" ? 404 : 403
            let code = scenario == "missing" ? "not_found" : "not_permitted"
            expected = .server(status: status, code: code)
            current = response("{\"error\":{\"code\":\"\(code)\"}}", status: status)
        case "offline":
            expected = .connectionUnavailable; current = .failure(expected)
        default:
            current = response(card.replacingOccurrences(of: #""eligible":true"#, with: #""eligible":false"#)
                .replacingOccurrences(of: #""reason":null"#, with: "\"reason\":\"\(scenario)\""))
        }
        let (account, disk, transport) = try await handoffAccount(current: current, now: now)
        let before = try #require(account.journal).snapshot
        await #expect(throws: expected) { try await PhoneHandoff.prepare(personID: 42, account: account, now: { now }) }
        #expect(account.journal?.snapshot == before)
        #expect(disk.value == nil)
        let requests = await transport.captured()
        #expect(requests.last?.url?.path == "/api/mobile/v1/buddy-checks/people/42")
        #expect(requests.last?.httpMethod == "GET")
        #expect(requests.filter { $0.httpMethod == "POST" }.count == 1) // OAuth only; no check submission.
    }
    @Test(arguments: ["draft", "pending", "disk_failure"])
    func phoneHandoffPreservesUnfinishedWorkAndRequiresDurableSave(_ scenario: String) async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-11T20:30:00Z"))
        let (account, disk, transport) = try await handoffAccount(current: response(dialableCard), now: now)
        let journal = try #require(account.journal)
        if scenario == "draft" {
            var draft = try ConnectedDraft(personID: 43, now: now)
            draft.notes = "Retain this unfinished synthetic check"
            try journal.saveDraft(draft)
        } else if scenario == "pending" { try journal.prepare(mutation()) }
        let before = journal.snapshot
        let persistedBefore = disk.value
        if scenario == "disk_failure" { disk.failWrites = true }
        let expected = scenario == "disk_failure" ? ClientError.journalUnavailable : .unfinishedOperation
        await #expect(throws: expected) { try await PhoneHandoff.prepare(personID: 42, account: account, now: { now }) }
        #expect(journal.snapshot == before)
        #expect(disk.value == persistedBefore)
        #expect(await transport.captured().filter { $0.httpMethod == "POST" }.count == 1)
    }
    private var dialableCard: String {
        cardJSON.replacingOccurrences(of: #""eligible":false"#, with: #""eligible":true"#)
            .replacingOccurrences(of: #""reason":"recent_attempt""#, with: #""reason":null"#)
            .replacingOccurrences(of: #""phone":null"#, with: #""phone":"+12025550100""#)
    }
    @Test(arguments: [-83.0, 83.0])
    func phoneHandoffUsesFreshServerAuthorityDespiteClockDifference(_ deviceOffset: Double) async throws {
        let serverNow = try #require(ISO8601DateFormatter().date(from: "2026-10-11T20:30:00Z"))
        let deviceNow = serverNow.addingTimeInterval(deviceOffset)
        let current = HTTPResponse(data: Data(dialableCard.utf8), status: 200,
                                   serverDate: serverNow, requestStartedAt: deviceNow)
        let (account, disk, transport) = try await handoffAccount(current: .success(current), now: deviceNow)
        let url = try await PhoneHandoff.prepare(personID: 42, account: account, now: { deviceNow.addingTimeInterval(0.5) })
        #expect(url.absoluteString == "tel:+12025550100")
        #expect(disk.value?.draft?.personID == 42 && disk.value?.draft?.outcome == nil)
        #expect(disk.value?.pending == nil)
        #expect(await transport.captured().filter { $0.httpMethod == "POST" }.count == 1)
    }
    @Test(arguments: ["expired", "slow_response", "paused", "future"])
    func clockAlignmentDoesNotExtendOrOverrideAuthority(_ scenario: String) async throws {
        let serverNow = try #require(ISO8601DateFormatter().date(from: "2026-10-11T20:30:00Z"))
        let deviceNow = serverNow.addingTimeInterval(83)
        var card = dialableCard
        if scenario == "expired" { card = card.replacingOccurrences(of: "20:31:00", with: "20:30:00") }
        if scenario == "future" { card = card.replacingOccurrences(of: "20:30:00", with: "20:30:10") }
        if scenario == "paused" {
            card = card.replacingOccurrences(of: #""eligible":true"#, with: #""eligible":false"#)
                .replacingOccurrences(of: #""reason":null"#, with: #""reason":"contact_paused""#)
        }
        let current = HTTPResponse(data: Data(card.utf8), status: 200,
                                   serverDate: serverNow, requestStartedAt: deviceNow)
        let (account, disk, _) = try await handoffAccount(current: .success(current), now: deviceNow)
        let receivedAt = deviceNow.addingTimeInterval(scenario == "slow_response" ? 60 : 0.5)
        await #expect(throws: ClientError.invalidInput) {
            try await PhoneHandoff.prepare(personID: 42, account: account, now: { receivedAt })
        }
        #expect(disk.value == nil)
        #expect(account.journal?.snapshot.draft == nil)
    }
    @Test func delayedPhoneReturnRequiresSignInButNeverChoosesAnOutcomeOrSubmits() async throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-11T20:30:00Z"))
        let later = start.addingTimeInterval(2 * 24 * 3600)
        func token(at date: Date) -> Result<HTTPResponse, ClientError> {
            response("{\"access_token\":\"synthetic-token\",\"token_type\":\"Bearer\",\"expires_in\":900,\"scope\":\"buddy_check\",\"created_at\":\(Int(date.timeIntervalSince1970))}")
        }
        let transport = StubTransport([token(at: start), response(sessionJSON), response(dialableCard),
                                       token(at: later), response(sessionJSON)])
        let disk = TestJournal(), vault = TestVault()
        func account() throws -> ConnectedAccount {
            ConnectedAccount(client: BuddyCheckClient(configuration: try configuration(), transport: transport),
                             vault: vault, persistence: disk)
        }
        func authorize(_ account: ConnectedAccount, at date: Date) async throws {
            let attempt = try account.beginAuthorization(now: date)
            try await account.finishAuthorization(callback: URL(string: attempt.configuration.redirectURI.absoluteString + "?code=test&state=" + attempt.state)!, now: date)
        }
        let first = try account()
        try await authorize(first, at: start)
        _ = try await PhoneHandoff.prepare(personID: 42, account: first, now: { start })
        let original = try #require(disk.value?.draft)
        first.lock()
        let reopened = try account()
        try await reopened.restore(now: later)
        #expect(reopened.needsSignIn && reopened.session == nil && reopened.journal == nil)
        #expect(disk.value?.draft == original && disk.value?.pending == nil)
        try await authorize(reopened, at: later)
        #expect(reopened.journal?.snapshot.draft == original)
        #expect(reopened.journal?.snapshot.draft?.outcome == nil)
        #expect(reopened.journal?.snapshot.pending == nil)
        let posts = await transport.captured().filter { $0.httpMethod == "POST" }
        #expect(posts.count == 2 && posts.allSatisfy { $0.url?.path == "/oauth/token" })
    }
    private func handoffAccount(current: Result<HTTPResponse, ClientError>, now: Date) async throws -> (ConnectedAccount, TestJournal, StubTransport) {
        let token = "{\"access_token\":\"synthetic-token\",\"token_type\":\"Bearer\",\"expires_in\":900,\"scope\":\"buddy_check\",\"created_at\":\(Int(now.timeIntervalSince1970))}"
        let transport = StubTransport([response(token), response(sessionJSON), current])
        let disk = TestJournal()
        let account = ConnectedAccount(client: BuddyCheckClient(configuration: try configuration(), transport: transport), vault: TestVault(), persistence: disk)
        let attempt = try account.beginAuthorization(now: now)
        try await account.finishAuthorization(callback: URL(string: attempt.configuration.redirectURI.absoluteString + "?code=test&state=" + attempt.state)!, now: now)
        return (account, disk, transport)
    }
    @Test func contactCopyNeverExportsUnpermittedFieldsOrUnreviewedAddress() throws {
        let json = """
        {"person_id":42,"source":"legion_post_tools/person/42","version":"test-version",
        "fields":{"first_name":"Alex","last_name":"Example","company":"American Legion Post 165","phone":"+12025550100","email":"alex@example.test",
        "address":{"street":"12 Example Way"}},"permitted_fields":["first_name","last_name","company","email"],
        "address_coverage":"reviewed_components","address_review_id":3,"checked_at":"2026-10-11T20:30:00.000000Z"}
        """
        let copy = try PermittedContactCopy(WireJSON.decoder().decode(ContactExportResponse.self, from: Data(json.utf8)))
        #expect(copy.company == "American Legion Post 165")
        #expect(copy.phone == nil && copy.address == nil && copy.email == "alex@example.test")
        let allowed = json.replacingOccurrences(of: #""company","email""#, with: #""company","email","address""#)
        let reviewed = try PermittedContactCopy(WireJSON.decoder().decode(ContactExportResponse.self, from: Data(allowed.utf8)))
        #expect(reviewed.address?.street == "12 Example Way")
        #expect(reviewed.address?.city == nil && reviewed.address?.postalCode == nil)
        let unknown = allowed.replacingOccurrences(of: "reviewed_components", with: "unknown")
        #expect(try PermittedContactCopy(WireJSON.decoder().decode(ContactExportResponse.self, from: Data(unknown.utf8))).address == nil)
    }
}

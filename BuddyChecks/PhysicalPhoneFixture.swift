#if DEBUG && !targetEnvironment(simulator)
import Foundation
import BuddyCheckAPI

/// Explicitly armed with a user-approved number; never used by normal fixtures.
/// No network calls, Post writes, automatic dialing or notification scheduling.
@MainActor enum PhysicalPhoneFixture {
    private struct Configuration: Codable {
        let run: UUID
        let phone: String
        let expires: Date
    }
    private static let control = DeviceKeychain(service: "org.wipost165.buddychecks.phone-test-control")
    private static let key = "approved-run"

    static func accountIfEnabled() async throws -> ConnectedAccount? {
        let environment = ProcessInfo.processInfo.environment
        // A run-scoped cleanup request lets the next ordinary foreground launch
        // remove the fixture without requiring Andre to keep the phone unlocked.
        // The marker contains only the approved run UUID, never the phone number.
        let resetFile = URL.applicationSupportDirectory.appendingPathComponent("BuddyChecks/PhoneHandoffTests/reset-run.txt")
        let resetRun = (try? String(contentsOf: resetFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        var configuration = try control.read(key).map { try JSONDecoder().decode(Configuration.self, from: $0) }
        if let retained = configuration, retained.expires <= Date() || environment["BUDDY_CHECKS_PHONE_TEST_RESET"] == "1" || resetRun == retained.run.uuidString {
            try await clear(retained)
            if resetRun == retained.run.uuidString { try FileManager.default.removeItem(at: resetFile) }
            configuration = nil
        }
        if let runValue = environment["BUDDY_CHECKS_PHONE_TEST_RUN"] {
            guard environment["BUDDY_CHECKS_PHONE_TEST_RESET"] != "1",
                  let run = UUID(uuidString: runValue),
                  let phone = environment["BUDDY_CHECKS_PHONE_TEST_NUMBER"],
                  phone.hasPrefix("+"), (8...16).contains(phone.count),
                  phone.dropFirst().allSatisfy({ "0123456789".contains($0) })
            else { throw ClientError.invalidConfiguration }
            if let retained = configuration {
                guard retained.run == run, retained.phone == phone else { throw ClientError.unfinishedOperation }
            } else {
                configuration = Configuration(run: run, phone: phone, expires: Date().addingTimeInterval(3600))
                try control.write(JSONEncoder().encode(configuration!), key: key)
            }
        }
        guard let configuration else { return nil }
        let account = try makeAccount(configuration)
        try await account.restore()
        if account.session == nil {
            let attempt = try account.beginAuthorization()
            let callback = URL(string: attempt.configuration.redirectURI.absoluteString + "?code=synthetic-code&state=" + attempt.state)!
            try await account.finishAuthorization(callback: callback)
        }
        return account
    }

    private static func directory(_ configuration: Configuration) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("BuddyChecks/PhoneHandoffTests", isDirectory: true)
            .appendingPathComponent(configuration.run.uuidString, isDirectory: true)
    }
    private static func makeAccount(_ configuration: Configuration) throws -> ConnectedAccount {
        let connection = try ConnectionConfiguration(issuer: URL(string: "https://synthetic.example.test")!,
                                                    clientID: "synthetic-public-client",
                                                    redirectURI: URL(string: "org.wipost165.buddychecks:/oauth/callback")!)
        let vault = DeviceKeychain(service: "org.wipost165.buddychecks.phone-test." + configuration.run.uuidString)
        let journal = EncryptedJournal(directory: directory(configuration), vault: vault)
        let transport = try PhysicalPhoneTransport(phone: configuration.phone)
        return ConnectedAccount(client: BuddyCheckClient(configuration: connection, transport: transport),
                                vault: vault, persistence: journal)
    }
    private static func clear(_ configuration: Configuration) async throws {
        let account = try makeAccount(configuration)
        // Restore scope before purging; the synthetic service has no external state.
        try await account.restore()
        _ = try await account.signOut()
        let folder = directory(configuration)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        try control.remove(key)
    }
}

private actor PhysicalPhoneTransport: HTTPTransport {
    let phone: String
    let fixture: FixtureTransport
    init(phone: String) throws {
        self.phone = phone
        fixture = try FixtureTransport(loseFirstResponse: false, permitsExport: false, paused: false,
                                       staleCorrection: false, changedFollowUp: false,
                                       contactFirstName: "Phone", contactLastName: "Test")
    }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let path = request.url?.path ?? ""
        guard request.httpMethod == "GET" || path == "/oauth/token" || path == "/oauth/revoke" else {
            throw ClientError.server(status: 403, code: "phone_test_read_only")
        }
        let response = try await fixture.send(request)
        guard path == "/api/mobile/v1/buddy-checks/people/42" || path == "/api/mobile/v1/session" else { return response }
        var object = try JSONSerialization.jsonObject(with: response.data) as! [String: Any]
        if path.hasSuffix("/people/42") { object["phone"] = phone }
        else if var installation = object["installation"] as? [String: Any] {
            installation["name"] = "Phone handoff test"; object["installation"] = installation
        }
        return HTTPResponse(data: try JSONSerialization.data(withJSONObject: object), status: response.status)
    }
}
#endif

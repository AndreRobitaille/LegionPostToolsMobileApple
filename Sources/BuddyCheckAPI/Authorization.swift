import CryptoKit
import Foundation
import Security

public struct ConnectionConfiguration: Codable, Equatable, Sendable {
    public let issuer: URL
    public let clientID: String
    public let redirectURI: URL
    public init(issuer: URL, clientID: String, redirectURI: URL) throws {
        guard var parts = URLComponents(url: issuer, resolvingAgainstBaseURL: false),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", !clientID.isEmpty,
              let callback = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false),
              let scheme = callback.scheme, !scheme.isEmpty, scheme != "http",
              callback.user == nil, callback.password == nil, callback.query == nil, callback.fragment == nil
        else { throw ClientError.invalidConfiguration }
        parts.path = ""
        guard let origin = parts.url else { throw ClientError.invalidConfiguration }
        self.issuer = origin
        self.clientID = clientID
        self.redirectURI = redirectURI
    }
    public func endpoint(_ path: String) -> URL { issuer.appendingPathComponent(path) }
}

public struct AuthorizationAttempt: Codable, Equatable, Sendable {
    public let configuration: ConnectionConfiguration
    public let state: String
    public let verifier: String
    public let startedAt: Date
    // Optional fields keep pre-upgrade Keychain attempts readable.
    public let rememberSession: Bool?
    public let exchangeId: UUID?

    public init(configuration: ConnectionConfiguration, now: Date = Date(), rememberSession: Bool = false) throws {
        self.configuration = configuration
        state = try Self.randomString()
        verifier = try Self.randomString()
        startedAt = now
        self.rememberSession = rememberSession
        exchangeId = rememberSession ? UUID() : nil
    }
    // Internal initializer permits the RFC 7636 published vector in tests.
    init(configuration: ConnectionConfiguration, state: String, verifier: String, startedAt: Date) {
        self.configuration = configuration; self.state = state; self.verifier = verifier; self.startedAt = startedAt
        rememberSession = false; exchangeId = nil
    }
    public var challenge: String { Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    public var authorizationURL: URL {
        var components = URLComponents(url: configuration.endpoint("oauth/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "buddy_check"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        if rememberSession == true { components.queryItems?.append(URLQueryItem(name: "remember_session", value: "180_days")) }
        return components.url!
    }
    public func code(from callback: URL, currentConfiguration: ConnectionConfiguration, now: Date = Date()) throws -> String {
        guard currentConfiguration == configuration, now >= startedAt,
              now.timeIntervalSince(startedAt) <= 600,
              var parts = URLComponents(url: callback, resolvingAgainstBaseURL: false), parts.fragment == nil
        else { throw ClientError.invalidCallback }
        let items = parts.queryItems ?? []
        parts.query = nil
        guard parts.url == configuration.redirectURI,
              Set(items.map(\.name)).count == items.count,
              items.first(where: { $0.name == "state" })?.value == state,
              !items.contains(where: { $0.name == "error" }),
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty,
              items.first(where: { $0.name == "iss" }).map({ $0.value == configuration.issuer.absoluteString }) ?? true
        else { throw ClientError.invalidCallback }
        return code
    }
    private static func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ClientError.journalUnavailable
        }
        return base64URL(Data(bytes))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

public struct AccessCredential: Codable, Equatable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int
    public let scope: String
    public let createdAt: Int
    public let refreshToken: String?
    public let issuer: URL?
    public let installationId: Int?
    public let userId: Int?
    public let sessionId: Int?
    public let rememberedSessionId: UUID?
    public let authorizedAt: Date?
    public let rememberedUntil: Date?
    public let serverExpiresAt: Date?
    private var localExpiresAt: Date? = nil
    private enum CodingKeys: String, CodingKey {
        case accessToken, tokenType, expiresIn, scope, createdAt, refreshToken, issuer, installationId, userId, sessionId
        case rememberedSessionId, authorizedAt, rememberedUntil, localExpiresAt
        case serverExpiresAt = "expiresAt"
    }
    public var expiresAt: Date {
        localExpiresAt ?? serverExpiresAt ?? Date(timeIntervalSince1970: TimeInterval(createdAt) + TimeInterval(expiresIn))
    }
    public func isValid(at now: Date) -> Bool { now < expiresAt }
    public var isRemembered: Bool { refreshToken != nil }
    func aligned(to response: HTTPResponse) -> Self {
        var result = self
        // This field is persisted locally, never trusted from the wire.
        result.localExpiresAt = nil
        if let serverDate = response.serverDate, let start = response.requestStartedAt {
            result.localExpiresAt = start.addingTimeInterval(result.expiresAt.timeIntervalSince(serverDate) - 1)
        }
        return result
    }
    func matches(_ session: MobileSession) -> Bool {
        guard isRemembered == session.capabilities.refresh else { return false }
        guard isRemembered else { return true }
        return issuer?.absoluteString == session.installation.issuer && installationId == session.installation.id &&
            userId == session.user.id && sessionId == session.sessionId && rememberedSessionId == session.rememberedSessionId &&
            authorizedAt == session.authorizedAt && rememberedUntil == session.rememberedUntil &&
            serverExpiresAt == session.expiresAt
    }
}

extension BuddyCheckClient {
    public func exchange(_ callback: URL, attempt: AuthorizationAttempt, now: Date = Date(), timeout: TimeInterval = 30) async throws -> AccessCredential {
        let code = try attempt.code(from: callback, currentConfiguration: configuration, now: now)
        var values = [
            "grant_type": "authorization_code", "client_id": configuration.clientID,
            "redirect_uri": configuration.redirectURI.absoluteString, "code": code, "code_verifier": attempt.verifier
        ]
        if attempt.rememberSession == true {
            guard let id = attempt.exchangeId else { throw ClientError.invalidCallback }
            values["exchange_id"] = id.uuidString.lowercased()
        }
        var request = formRequest(path: "oauth/token", values: values)
        request.timeoutInterval = max(1, min(30, timeout))
        let response = try await transport.send(request)
        return try credential(response, remembered: attempt.rememberSession == true, now: now)
    }
    public func renew(_ previous: AccessCredential, exchangeID: UUID, now: Date = Date(), timeout: TimeInterval = 30) async throws -> AccessCredential {
        guard let refresh = previous.refreshToken, !refresh.isEmpty else { throw ClientError.signInRequired }
        var request = formRequest(path: "oauth/token", values: [
            "grant_type": "refresh_token", "client_id": configuration.clientID,
            "refresh_token": refresh, "exchange_id": exchangeID.uuidString.lowercased()
        ])
        request.timeoutInterval = max(1, min(30, timeout))
        let response = try await transport.send(request)
        let result = try credential(response, remembered: true, now: now)
        guard result.issuer == previous.issuer, result.installationId == previous.installationId,
              result.userId == previous.userId, result.rememberedSessionId == previous.rememberedSessionId,
              result.authorizedAt == previous.authorizedAt, result.rememberedUntil == previous.rememberedUntil,
              result.sessionId != previous.sessionId, result.refreshToken != previous.refreshToken,
              result.accessToken != previous.accessToken else { throw ClientError.invalidResponse }
        return result
    }
    private func credential(_ response: HTTPResponse, remembered: Bool, now: Date) throws -> AccessCredential {
        guard response.status == 200 else { throw oauthError(response) }
        guard let credential = try? WireJSON.decoder().decode(AccessCredential.self, from: response.data),
              credential.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame,
              !credential.accessToken.isEmpty, credential.scope == "buddy_check",
              (1...900).contains(credential.expiresIn), credential.createdAt > 0,
              credential.isRemembered == remembered
        else { throw ClientError.invalidResponse }
        if remembered {
            guard let refresh = credential.refreshToken, !refresh.isEmpty, refresh != credential.accessToken,
                  credential.issuer == configuration.issuer,
                  let installation = credential.installationId, installation > 0,
                  let user = credential.userId, user > 0,
                  let session = credential.sessionId, session > 0, credential.rememberedSessionId != nil,
                  let authorized = credential.authorizedAt, let until = credential.rememberedUntil,
                  authorized.timeIntervalSince1970 <= TimeInterval(credential.createdAt) + 1,
                  until > authorized, until.timeIntervalSince(authorized) <= 180 * 24 * 3600 + 1,
                  let expires = credential.serverExpiresAt,
                  expires > Date(timeIntervalSince1970: TimeInterval(credential.createdAt)),
                  expires <= until,
                  expires.timeIntervalSince1970 - TimeInterval(credential.createdAt) <= 901,
                  TimeInterval(credential.expiresIn) <= expires.timeIntervalSince1970 - TimeInterval(credential.createdAt) + 1
            else { throw ClientError.invalidResponse }
        }
        let aligned = credential.aligned(to: response)
        guard aligned.isValid(at: now) else { throw ClientError.invalidResponse }
        return aligned
    }
    public func revoke(_ credential: AccessCredential) async throws {
        let response = try await transport.send(formRequest(path: "oauth/revoke", values: [
            "client_id": configuration.clientID, "token": credential.refreshToken ?? credential.accessToken
        ]))
        guard response.status == 200 else { throw oauthError(response) }
    }
    private func formRequest(path: String, values: [String: String]) -> URLRequest {
        var request = URLRequest(url: configuration.endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        request.httpBody = Data(values.sorted(by: { $0.key < $1.key }).map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
        return request
    }
    private func oauthError(_ response: HTTPResponse) -> ClientError {
        struct OAuthError: Decodable { let error: String; let errorCode: String? }
        let value = try? WireJSON.decoder().decode(OAuthError.self, from: response.data)
        return .server(status: response.status, code: value?.errorCode ?? value?.error ?? "unavailable")
    }
}

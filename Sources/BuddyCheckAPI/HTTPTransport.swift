import Foundation

public struct HTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public let serverDate: Date?
    public let requestStartedAt: Date?
    public init(data: Data, status: Int, serverDate: Date? = nil, requestStartedAt: Date? = nil) {
        self.data = data; self.status = status
        self.serverDate = serverDate; self.requestStartedAt = requestStartedAt
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public final class PrivateHTTPTransport: HTTPTransport, Sendable {
    private let session: URLSession
    private let delegate: NoRedirects
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let delegate = NoRedirects()
        self.delegate = delegate
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let startedAt = Date()
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            let serverDate = http.value(forHTTPHeaderField: "Date").flatMap(formatter.date(from:))
            return HTTPResponse(data: data, status: http.statusCode, serverDate: serverDate, requestStartedAt: startedAt)
        } catch is CancellationError { throw CancellationError() }
        catch let error as ClientError { throw error }
        catch { throw ClientError.connectionUnavailable }
    }
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}

public enum ClientError: Error, Equatable, Sendable, LocalizedError {
    case invalidConfiguration, invalidInput, invalidCallback, invalidResponse
    case connectionUnavailable, accountMismatch, unfinishedOperation, journalUnavailable, signInRequired
    case server(status: Int, code: String)
    public var requiresSignIn: Bool {
        if self == .signInRequired { return true }
        if case let .server(_, code) = self,
           ["remembered_session_expired", "invalid_refresh_token", "invalid_authorization_code"].contains(code) { return true }
        if case let .server(status, _) = self { return status == 401 }
        return false
    }
    public var confirmsRevocation: Bool {
        switch self {
        case let .server(status, code):
            [400, 401, 403].contains(status) && ["revoked_session", "account_unavailable", "refresh_reuse_detected"].contains(code)
        default: false
        }
    }
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Check the Post connection settings."
        case .invalidInput: "Review the entered details."
        case .invalidCallback: "Sign-in could not be verified. Start sign-in again."
        case .invalidResponse: "The Post returned an unexpected response. Your pending work has not been marked saved."
        case .connectionUnavailable: "The Post could not be reached. Your pending work is still on this device."
        case .accountMismatch: "Sign in to the same Post and account to recover this work."
        case .unfinishedOperation: "Resolve the pending submission before starting another."
        case .journalUnavailable: "Protected storage is unavailable. No new submission was sent."
        case .signInRequired: "Sign in again to continue. Your unfinished work is retained."
        case .server(_, "expired_session"), .server(_, "invalid_session"): "Sign in again to continue. Your unfinished work is retained."
        case .server(_, "remembered_session_expired"), .server(_, "invalid_refresh_token"), .server(_, "invalid_authorization_code"):
            "Sign in again to continue. Your unfinished work is retained."
        case .server(_, "revoked_session"), .server(_, "account_unavailable"), .server(_, "refresh_reuse_detected"):
            "Access ended. Sign in again before continuing."
        case .server(_, "contact_paused"): "Contact with this member is paused."
        case .server(_, "export_disabled"), .server(_, "export_not_permitted"): "The Post does not permit this Contacts copy."
        case .server(_, "not_found"): "This record is unavailable. A missing receipt does not establish whether the check was saved."
        case .server(_, "operation_payload_conflict"), .server(_, "stale_revision"), .server(_, "follow_up_closed"):
            "This record changed. Refresh and review it before making a new submission."
        case .server(_, "invalid_request"): "The Post could not accept these details. Review the entry before resubmitting."
        case .server: "The Post service is unavailable. Try again later."
        }
    }
}

struct ErrorEnvelope: Decodable { let error: Details; struct Details: Decodable { let code: String } }

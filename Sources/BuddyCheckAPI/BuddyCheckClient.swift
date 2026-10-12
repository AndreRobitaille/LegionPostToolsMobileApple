import Foundation

public struct BuddyCheckClient: Sendable {
    public let configuration: ConnectionConfiguration
    let transport: any HTTPTransport
    public init(configuration: ConnectionConfiguration, transport: any HTTPTransport = PrivateHTTPTransport()) {
        self.configuration = configuration; self.transport = transport
    }
    public func session(token: String) async throws -> MobileSession {
        let result: MobileSession = try await get("session", token: token)
        guard result.installation.issuer == configuration.issuer.absoluteString,
              result.installation.id > 0, result.user.id > 0, result.capabilities.buddyChecks,
              result.sessionId > 0, TimeZone(identifier: result.installation.timezone) != nil
        else { throw ClientError.invalidResponse }
        if result.capabilities.refresh {
            guard result.rememberedSessionId != nil, let authorized = result.authorizedAt,
                  let until = result.rememberedUntil, until > authorized,
                  until.timeIntervalSince(authorized) <= 180 * 24 * 3600 + 1 else { throw ClientError.invalidResponse }
        }
        return result
    }
    public func people(query: String, cursor: String? = nil, limit: Int = 25, token: String) async throws -> PageResponse<PersonIdentity> {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(query.count) else { throw ClientError.invalidInput }
        return try await get("buddy-checks/people", query: pagination(cursor, limit) + [URLQueryItem(name: "q", value: query)], token: token)
    }
    public func person(_ id: Int, token: String) async throws -> PersonCardResponse {
        try positive(id)
        let response = try await transport.send(request("buddy-checks/people/\(id)", token: token))
        var card: PersonCardResponse = try decode(response, status: 200)
        guard card.id == id else { throw ClientError.invalidResponse }
        if let serverDate = response.serverDate, let startedAt = response.requestStartedAt {
            card.eligibility = card.eligibility.aligned(serverDate: serverDate, requestStartedAt: startedAt)
        }
        return card
    }
    public func suggestion(excluding ids: [Int] = [], token: String) async throws -> SuggestionResponse {
        guard ids.count <= 50, ids.allSatisfy({ $0 > 0 }) else { throw ClientError.invalidInput }
        let result: SuggestionResponse = try await get("buddy-checks/suggestion", query: ids.map { URLQueryItem(name: "exclude_ids[]", value: String($0)) }, token: token)
        if let random = result.randomCandidates, !random.isEmpty {
            guard result.state == .insufficientHistory, random.count <= 3,
                  Set(random.map(\.id)).count == random.count,
                  random.allSatisfy({ $0.id > 0 && !ids.contains($0.id) }) else { throw ClientError.invalidResponse }
        }
        if result.state == .candidate {
            guard let person = result.person, person.id > 0, !ids.contains(person.id),
                  result.eligibility?.eligible == true,
                  ["two_recorded_absences", "recorded_contact_is_older"].contains(result.reason), result.reasonOn != nil
            else { throw ClientError.invalidResponse }
        }
        return result
    }
    public func history(cursor: String? = nil, limit: Int = 25, token: String) async throws -> PageResponse<ContactRecord> {
        try await get("buddy-checks/mine", query: pagination(cursor, limit), token: token)
    }
    public func revisions(contactID: Int, cursor: String? = nil, limit: Int = 25, token: String) async throws -> PageResponse<ContactRecord> {
        try positive(contactID)
        return try await get("buddy-checks/\(contactID)/revisions", query: pagination(cursor, limit), token: token)
    }
    public func followUps(cursor: String? = nil, limit: Int = 25, token: String) async throws -> PageResponse<FollowUpRecord> {
        try await get("buddy-checks/follow-ups", query: pagination(cursor, limit), token: token)
    }
    /// Resolve a selected row through the current caller-owned endpoint. Never
    /// use the old list value when authority, identity or pagination is uncertain.
    public func currentFollowUp(_ previous: FollowUpRecord, token: String) async throws -> FollowUpRecord {
        try positive(previous.id); try positive(previous.personId)
        // Follow-ups use lock_version (starting at zero); contact revisions start at one.
        guard previous.revision >= 0 else { throw ClientError.invalidInput }
        let current = try await followUp(id: previous.id, token: token)
        guard current.personId == previous.personId, current.revision >= previous.revision else { throw ClientError.invalidResponse }
        return current
    }
    /// Resolve an opaque reminder reference without retaining a downloaded card.
    public func followUp(id: Int, token: String) async throws -> FollowUpRecord {
        try positive(id)
        var cursor: String?
        var seen = Set<String>()
        repeat {
            try Task.checkCancellation()
            let page = try await followUps(cursor: cursor, token: token)
            let matches = page.items.filter { $0.id == id }
            guard matches.count <= 1 else { throw ClientError.invalidResponse }
            if let current = matches.first {
                guard current.personId > 0, current.revision >= 0, current.dueAt.timeIntervalSince1970.isFinite,
                      TimeZone(identifier: current.entryZone) != nil else { throw ClientError.invalidResponse }
                return current
            }
            cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw ClientError.invalidResponse }
        } while cursor != nil
        throw ClientError.server(status: 404, code: "not_found")
    }
    public func snoozes(cursor: String? = nil, limit: Int = 25, token: String) async throws -> PageResponse<SnoozeRecord> {
        try await get("buddy-checks/snoozes", query: pagination(cursor, limit), token: token)
    }
    public func contactExport(personID: Int, token: String) async throws -> ContactExportResponse {
        try positive(personID)
        let result: ContactExportResponse = try await get("people/\(personID)/contact-export", token: token)
        guard result.personId == personID, result.source == "legion_post_tools/person/\(personID)", !result.version.isEmpty else {
            throw ClientError.invalidResponse
        }
        return result
    }
    public func receipt(operationID: UUID, token: String) async throws -> MutationReceipt {
        let result: MutationReceipt = try await get("buddy-checks/receipts/\(operationID.uuidString.lowercased())", token: token)
        try validate(result, operationID: operationID)
        return result
    }
    public func submit(_ operation: PendingMutation, token: String) async throws -> MutationReceipt {
        // Send these exact persisted bytes, including after a renewed session.
        var request = request(operation.route.path, token: token)
        request.httpMethod = operation.route.method
        request.httpBody = operation.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let result: MutationReceipt = try await decode(request, status: 201)
        try validate(result, operationID: operation.id)
        guard operation.matches(result) else { throw ClientError.invalidResponse }
        return result
    }
    private func validate(_ receipt: MutationReceipt, operationID: UUID) throws {
        guard receipt.operationId == operationID, receipt.state == "accepted",
              receipt.contact != nil || receipt.followUp != nil || receipt.snooze != nil else {
            throw ClientError.invalidResponse
        }
    }
    private func pagination(_ cursor: String?, _ limit: Int) throws -> [URLQueryItem] {
        guard (1...50).contains(limit), cursor.map({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) ?? true else {
            throw ClientError.invalidInput
        }
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return items
    }
    private func positive(_ id: Int) throws { guard id > 0 else { throw ClientError.invalidInput } }
    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], token: String) async throws -> T {
        var request = request(path, token: token)
        var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            url.queryItems = query
            // Rails decodes query strings as forms: a literal plus must remain
            // a plus in a name instead of becoming a space.
            url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            request.url = url.url
        }
        return try await decode(request, status: 200)
    }
    private func request(_ path: String, token: String) -> URLRequest {
        var request = URLRequest(url: configuration.endpoint("api/mobile/v1/" + path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return request
    }
    private func decode<T: Decodable>(_ request: URLRequest, status: Int) async throws -> T {
        let response = try await transport.send(request)
        return try decode(response, status: status)
    }
    private func decode<T: Decodable>(_ response: HTTPResponse, status: Int) throws -> T {
        guard response.status == status else {
            let code = (try? WireJSON.decoder().decode(ErrorEnvelope.self, from: response.data).error.code) ?? "unavailable"
            throw ClientError.server(status: response.status, code: code)
        }
        guard let value = try? WireJSON.decoder().decode(T.self, from: response.data) else { throw ClientError.invalidResponse }
        return value
    }
}

import Foundation

// Wire models deliberately keep server integer identities separate from the
// synthetic app's UUIDs. No downloaded model is part of the durable journal.
public struct MobileSession: Codable, Equatable, Sendable {
    public let installation: Installation
    public let user: Human
    public let sessionId: Int
    public let expiresAt: Date
    public let capabilities: Capabilities
    public let rememberedSessionId: UUID?
    public let authorizedAt: Date?
    public let rememberedUntil: Date?
    public struct Installation: Codable, Equatable, Sendable {
        public let id: Int
        public let issuer: String
        public let name: String
        public let timezone: String
    }
    public struct Human: Codable, Equatable, Sendable {
        public let id: Int
        public let name: String
    }
    public struct Capabilities: Codable, Equatable, Sendable {
        public let buddyChecks: Bool
        public let contactsExport: Bool
        public let refresh: Bool
    }
}

public struct PersonIdentity: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let firstName: String
    public let lastName: String
    public var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

public struct PersonCardResponse: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let firstName: String
    public let lastName: String
    public let phone: String?
    public let email: String?
    public let assignmentIds: [Int]
    public let exportAvailable: Bool
    public internal(set) var eligibility: Eligibility
    public let coverage: Coverage
    public var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

public struct Eligibility: Codable, Equatable, Sendable {
    public let eligible: Bool
    public let reason: String?
    public let checkedAt: Date
    public let expiresAt: Date
    private var serverClockOffset: TimeInterval? = nil
    private enum CodingKeys: String, CodingKey { case eligible, reason, checkedAt, expiresAt }
    public func permitsHandoff(at now: Date) -> Bool {
        let serverNow = now.addingTimeInterval(serverClockOffset ?? 0)
        return eligible && reason == nil && checkedAt <= serverNow && serverNow < expiresAt
    }
    func aligned(serverDate: Date, requestStartedAt: Date) -> Self {
        var value = self
        // HTTP Date is rounded to seconds. Using its upper bound at request start
        // also charges the entire round trip against the lease, never extending it.
        value.serverClockOffset = serverDate.timeIntervalSince(requestStartedAt) + 1
        return value
    }
}

public struct Coverage: Codable, Equatable, Sendable {
    public let contactHistory: String
    public let missingHistory: String
    public let attendance: String
    public let checkedAt: Date
}

public struct SuggestionResponse: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case candidate, exhausted, insufficientHistory = "insufficient_history" }
    public let state: State
    public let person: PersonIdentity?
    public let reason: String?
    public let reasonOn: String?
    public let attendance: Attendance?
    public let eligibility: Eligibility?
    public let coverage: Coverage
    public let randomCandidates: [PersonIdentity]?
    public struct Attendance: Codable, Equatable, Sendable {
        public let coverage: String
        public let meetings: [Meeting]
    }
    public struct Meeting: Codable, Equatable, Sendable {
        public let meetingId: Int
        public let startsAt: Date
        public let registerRevision: Int
    }
}

public struct PageResponse<Item: Codable & Sendable>: Codable, Sendable {
    public let items: [Item]
    public let nextCursor: String?
}

public struct ContactRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let sourceId: Int
    public let personId: Int
    public let revision: Int
    // Legacy outcomes/channels are retained verbatim for history, not silently
    // coerced into one of the narrower choices allowed for a new check.
    public let channel: String
    public let outcome: String
    public let precision: Precision
    public let occurredAt: Date?
    public let occurredOn: String
    public let entryZone: String?
    public let membershipYear: Int
    public let notes: String?
    public let legacyFollowUpOn: String?
    public let recordedAt: Date
    public enum Precision: String, Codable, Sendable { case instant, date }
}

public struct FollowUpRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let personId: Int
    public let contactId: Int?
    public let dueAt: Date
    public let entryZone: String
    public let status: Status
    public let revision: Int
    public enum Status: String, Codable, Sendable { case open, completed, cancelled }
}

public struct SnoozeRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let personId: Int
    public let untilAt: Date
    public let cancelledAt: Date?
    public let revision: Int
}

public struct MutationReceipt: Codable, Equatable, Sendable {
    public let operationId: UUID
    public let acceptedAt: Date
    public let state: String
    public let contact: ContactRecord?
    public let followUp: FollowUpRecord?
    public let snooze: SnoozeRecord?
}

public struct ContactExportResponse: Codable, Equatable, Sendable {
    public let personId: Int
    public let source: String
    public let version: String
    public let fields: Fields
    public let permittedFields: [String]
    public let addressCoverage: String
    public let addressReviewId: Int?
    public let checkedAt: Date
    public struct Fields: Codable, Equatable, Sendable {
        public let firstName: String
        public let lastName: String
        public let company: String
        public let phone: String?
        public let email: String?
        public let address: Address
    }
    public struct Address: Codable, Equatable, Sendable {
        public let street: String?
        public let city: String?
        public let state: String?
        public let postalCode: String?
        public let country: String?
    }
}

public enum WireJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let text = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO 8601 instant")
            }
            return date
        }
        return decoder
    }
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, value in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = value.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }
}

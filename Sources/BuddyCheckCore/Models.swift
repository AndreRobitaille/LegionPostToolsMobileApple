import Foundation

public struct ExternalReference: Codable, Hashable, Sendable {
    public var source: String
    public var identifier: String
    public init(source: String, identifier: String) {
        self.source = source; self.identifier = identifier
    }
}

public struct PostalAddress: Codable, Equatable, Sendable {
    public var street: String
    public var city: String
    public var state: String
    public var postalCode: String
    public var country: String
    public init(street: String, city: String, state: String, postalCode: String, country: String) {
        self.street = street; self.city = city; self.state = state
        self.postalCode = postalCode; self.country = country
    }
}

public struct Person: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var firstName: String
    public var lastName: String
    public var externalReference: ExternalReference?
    public var memberNumber: String?
    public var phone: String?
    public var email: String?
    public var address: PostalAddress?
    public var isSynthetic: Bool
    public var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }

    public init(id: UUID, firstName: String, lastName: String, externalReference: ExternalReference? = nil,
                memberNumber: String? = nil, phone: String? = nil, email: String? = nil,
                address: PostalAddress? = nil, isSynthetic: Bool) {
        self.id = id; self.firstName = firstName; self.lastName = lastName
        self.externalReference = externalReference; self.memberNumber = memberNumber
        self.phone = phone; self.email = email; self.address = address; self.isSynthetic = isSynthetic
    }
    public static func == (lhs: Person, rhs: Person) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct PostConfiguration: Sendable {
    public var shortName: String
    public var fullName: String
    public var location: String
    public var contactsCompany: String
    public var installationURL: URL?
    public init(shortName: String, fullName: String, location: String, contactsCompany: String,
                installationURL: URL? = nil) {
        self.shortName = shortName; self.fullName = fullName; self.location = location
        self.contactsCompany = contactsCompany; self.installationURL = installationURL
    }
    public static let synthetic = PostConfiguration(shortName: "Post 165", fullName: "Robert E. Burns",
                                                    location: "Two Rivers", contactsCompany: "American Legion Post 165")
}

public enum SyntheticDirectory {
    // Reserved fictional phone numbers and example.org addresses; never dial these fixtures.
    public static let people: [Person] = [
        Person(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, firstName: "Robert", lastName: "Miller",
               phone: "+12025550101", email: "robert.miller@example.org",
               address: PostalAddress(street: "100 Example Street", city: "Two Rivers", state: "WI", postalCode: "54241", country: "US"), isSynthetic: true),
        Person(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, firstName: "Elena", lastName: "Davis",
               phone: "+12025550102", email: "elena.davis@example.org", isSynthetic: true),
        Person(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, firstName: "James", lastName: "Wilson", isSynthetic: true)
    ]
}

public enum ContactMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case phone, text, visit
    public var id: Self { self }
    public var label: String { switch self { case .phone: "Phone call"; case .text: "Text message"; case .visit: "Visit" } }
}

public enum CheckOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case connected, noAnswer, wrongNumber, notAttempted
    public var id: Self { self }
    public var countsAsAttempt: Bool { self != .notAttempted }
    public func label(for method: ContactMethod) -> String {
        switch self {
        case .connected: method == .text ? "We exchanged messages" : "We talked"
        case .noAnswer: method == .text ? "No reply" : (method == .visit ? "Not available" : "No answer")
        case .wrongNumber: "Wrong number"
        case .notAttempted: switch method { case .phone: "I didn't call"; case .text: "I didn't send a text"; case .visit: "I didn't visit" }
        }
    }
    public static func choices(for method: ContactMethod) -> [Self] {
        method == .visit ? [.connected, .noAnswer, .notAttempted] : allCases
    }
}

public enum DraftOrigin: String, Codable, Sendable { case simulatedCall, manual, correction }
public enum DraftStage: String, Codable, Sendable { case details, outcome, reminder }

public struct CheckDraft: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let personID: UUID
    public var origin: DraftOrigin
    public var stage: DraftStage
    public var method: ContactMethod
    public var occurredAt: Date
    public var eventTimeZone: String
    public var outcome: CheckOutcome?
    public var followUpDue: Date?
    public var followUpTimeZone: String?
    public let startedAt: Date
}

public struct CheckRevision: Codable, Equatable, Sendable {
    public var changedAt: Date
    public var previousMethod: ContactMethod
    public var previousOutcome: CheckOutcome
    public var previousOccurredAt: Date
    public var previousTimeZone: String
}

public struct BuddyCheck: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let personID: UUID
    public var method: ContactMethod
    public var outcome: CheckOutcome
    public var occurredAt: Date
    public var eventTimeZone: String
    public let recordedAt: Date
    public var updatedAt: Date
    public var revisions: [CheckRevision]
    // Local-only until a reviewed transport and server receipt contract exists.
    public var storageLabel: String { "Saved on this iPhone" }
}

public enum FollowUpStatus: String, Codable, Sendable { case open, completed, cancelled }
public struct FollowUp: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let checkID: UUID
    public let personID: UUID
    public var due: Date
    public var timeZone: String
    public var status: FollowUpStatus
}

public struct LocalSnapshot: Codable, Equatable, Sendable {
    public var formatVersion = 5
    public var draft: CheckDraft?
    public var checks: [BuddyCheck] = []
    public var followUps: [FollowUp] = []
    public var contactLinks: [ContactLink] = []
    public var suggestionSnoozes: [SuggestionSnooze] = []
    public var reminderIDs: [UUID] = []
    public var reminderSnoozes: [UUID: Date] = [:]
    public init() {}
    private enum CodingKeys: String, CodingKey { case formatVersion, draft, checks, followUps, contactLinks, suggestionSnoozes, reminderIDs, reminderSnoozes }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .formatVersion)
        guard [1, 2, 3, 4, 5].contains(version) else { throw WorkflowError.unsupportedFormat }
        formatVersion = 5
        draft = try values.decodeIfPresent(CheckDraft.self, forKey: .draft)
        checks = try values.decode([BuddyCheck].self, forKey: .checks)
        followUps = try values.decode([FollowUp].self, forKey: .followUps)
        contactLinks = version == 1 ? [] : try values.decode([ContactLink].self, forKey: .contactLinks)
        suggestionSnoozes = version < 3 ? [] : try values.decode([SuggestionSnooze].self, forKey: .suggestionSnoozes)
        reminderIDs = version < 4 ? [] : try values.decode([UUID].self, forKey: .reminderIDs)
        reminderSnoozes = version < 5 ? [:] : try values.decode([UUID: Date].self, forKey: .reminderSnoozes)
    }
}

public enum WorkflowError: Error, LocalizedError, Equatable {
    case unfinishedCheck, missingDraft, missingPerson, missingCheck, missingFollowUp, missingOutcome
    case futureEvent, pastReminder, invalidOutcome, closedFollowUp, storageNotReady, unsupportedFormat, damagedStorage
    public var errorDescription: String? {
        switch self {
        case .unfinishedCheck: "A check is unfinished. Continue it or discard it before starting another."
        case .missingDraft: "This unfinished check is no longer available."
        case .missingPerson: "This person is no longer available."
        case .missingCheck: "This check is no longer available."
        case .missingFollowUp: "This follow-up is no longer available."
        case .missingOutcome: "Choose what happened before saving."
        case .futureEvent: "Choose when the contact happened, not a future time."
        case .pastReminder: "Choose a future date and time for the follow-up."
        case .invalidOutcome: "Choose an outcome that matches the contact method."
        case .closedFollowUp: "This follow-up is already closed."
        case .storageNotReady: "Your saved work could not be opened. Retry before making changes."
        case .unsupportedFormat: "This saved work needs a newer version of the app."
        case .damagedStorage: "Your saved work could not be read. It has been kept unchanged."
        }
    }
}

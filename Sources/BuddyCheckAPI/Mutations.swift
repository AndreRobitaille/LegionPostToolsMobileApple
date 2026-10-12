import Foundation

public enum CheckChannel: String, Codable, CaseIterable, Sendable { case phone, text, inPerson = "in_person" }
public enum CheckResult: String, Codable, CaseIterable, Sendable {
    case reached, noAnswer = "no_answer", messageLeft = "message_left", wrongNumber = "wrong_number", notAttempted = "not_attempted"
}

public struct CheckFacts: Codable, Equatable, Sendable {
    public let channel: String
    public let outcome: String
    public let occurredAt: Date?
    public let entryZone: String?
    public let occurredOn: String?
    public let notes: String?
    public init(channel: CheckChannel, outcome: CheckResult, occurredAt: Date, entryZone: String, notes: String? = nil) throws {
        guard TimeZone(identifier: entryZone) != nil, (notes?.count ?? 0) <= 2000 else { throw ClientError.invalidInput }
        self.channel = channel.rawValue; self.outcome = outcome.rawValue
        self.occurredAt = occurredAt; self.entryZone = entryZone; self.notes = notes; occurredOn = nil
    }
    public init(correcting legacy: ContactRecord, channel: CheckChannel, outcome: CheckResult, notes: String? = nil) throws {
        guard (notes?.count ?? 0) <= 2000 else { throw ClientError.invalidInput }
        self.channel = channel.rawValue; self.outcome = outcome.rawValue; self.notes = notes
        switch legacy.precision {
        case .date:
            occurredAt = nil; entryZone = nil; occurredOn = legacy.occurredOn
        case .instant:
            guard let instant = legacy.occurredAt, let zone = legacy.entryZone else { throw ClientError.invalidResponse }
            occurredAt = instant; entryZone = zone; occurredOn = nil
        }
    }
    public init(legacyDate: String, channel: CheckChannel, outcome: CheckResult, notes: String? = nil) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: legacyDate), formatter.string(from: date) == legacyDate,
              (notes?.count ?? 0) <= 2000 else { throw ClientError.invalidInput }
        self.channel = channel.rawValue; self.outcome = outcome.rawValue; self.notes = notes
        occurredOn = legacyDate; occurredAt = nil; entryZone = nil
    }
}

public struct FollowUpTime: Codable, Equatable, Sendable {
    public let dueAt: Date
    public let entryZone: String
    public init(dueAt: Date, entryZone: String) throws {
        guard TimeZone(identifier: entryZone) != nil else { throw ClientError.invalidInput }
        self.dueAt = dueAt; self.entryZone = entryZone
    }
}

public struct PendingMutation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let personID: Int
    public let route: Route
    public let expectedRevision: Int?
    public let body: Data
    public let createdAt: Date
    public enum Route: Codable, Equatable, Sendable {
        case record, correction(Int), schedule, followUpChange(Int), snooze, undoSnooze(Int)
        var path: String {
            switch self {
            case .record: "buddy-checks"
            case .correction(let id): "buddy-checks/\(id)/corrections"
            case .schedule: "buddy-checks/follow-ups"
            case .followUpChange(let id): "buddy-checks/follow-ups/\(id)/changes"
            case .snooze: "buddy-checks/snoozes"
            case .undoSnooze(let id): "buddy-checks/snoozes/\(id)"
            }
        }
        var method: String { if case .undoSnooze = self { "DELETE" } else { "POST" } }
    }
    private struct Payload: Codable {
        let operationId: UUID
        var personId: Int? = nil
        var facts: CheckFacts? = nil
        var assignmentId: Int? = nil
        var followUp: FollowUpTime? = nil
        var expectedRevision: Int? = nil
        var action: String? = nil
        var dueAt: Date? = nil
        var entryZone: String? = nil
        var untilAt: Date? = nil
    }
    private init(personID: Int, route: Route, payload: Payload, now: Date) throws {
        guard personID > 0, payload.expectedRevision.map({ $0 >= 0 }) ?? true else { throw ClientError.invalidInput }
        id = payload.operationId; self.personID = personID; self.route = route
        expectedRevision = payload.expectedRevision
        body = try WireJSON.encoder().encode(payload); createdAt = now
    }
    public static func record(personID: Int, facts: CheckFacts, assignmentID: Int? = nil, followUp: FollowUpTime? = nil,
                              operationID: UUID = UUID(), now: Date = Date()) throws -> Self {
        guard assignmentID.map({ $0 > 0 }) ?? true else { throw ClientError.invalidInput }
        return try Self(personID: personID, route: .record,
                        payload: Payload(operationId: operationID, personId: personID, facts: facts, assignmentId: assignmentID, followUp: followUp), now: now)
    }
    public static func correct(_ contact: ContactRecord, facts: CheckFacts, operationID: UUID = UUID(), now: Date = Date()) throws -> Self {
        try correct(personID: contact.personId, contactID: contact.id, expectedRevision: contact.revision, facts: facts, operationID: operationID, now: now)
    }
    public static func correct(personID: Int, contactID: Int, expectedRevision: Int, facts: CheckFacts, operationID: UUID = UUID(), now: Date = Date()) throws -> Self {
        guard contactID > 0, expectedRevision > 0 else { throw ClientError.invalidInput }
        return try Self(personID: personID, route: .correction(contactID),
                        payload: Payload(operationId: operationID, facts: facts, expectedRevision: expectedRevision), now: now)
    }
    public static func schedule(personID: Int, time: FollowUpTime, operationID: UUID = UUID(), now: Date = Date()) throws -> Self {
        try Self(personID: personID, route: .schedule, payload: Payload(operationId: operationID, personId: personID, dueAt: time.dueAt, entryZone: time.entryZone), now: now)
    }
    public enum FollowUpAction: Sendable { case reschedule(FollowUpTime), complete, cancel }
    public static func change(_ followUp: FollowUpRecord, action: FollowUpAction, operationID: UUID = UUID(), now: Date = Date()) throws -> Self {
        guard followUp.id > 0, followUp.status == .open else { throw ClientError.invalidInput }
        var payload = Payload(operationId: operationID, expectedRevision: followUp.revision)
        switch action {
        case .reschedule(let time): payload.action = "reschedule"; payload.dueAt = time.dueAt; payload.entryZone = time.entryZone
        case .complete: payload.action = "complete"
        case .cancel: payload.action = "cancel"
        }
        return try Self(personID: followUp.personId, route: .followUpChange(followUp.id), payload: payload, now: now)
    }
    public static func snooze(personID: Int, until: Date, operationID: UUID = UUID(), now: Date = Date()) throws -> Self {
        try Self(personID: personID, route: .snooze, payload: Payload(operationId: operationID, personId: personID, untilAt: until), now: now)
    }
    public static func undo(_ snooze: SnoozeRecord, operationID: UUID = UUID(), now: Date = Date()) throws -> Self {
        guard snooze.id > 0 else { throw ClientError.invalidInput }
        return try Self(personID: snooze.personId, route: .undoSnooze(snooze.id), payload: Payload(operationId: operationID, expectedRevision: snooze.revision), now: now)
    }
    func matches(_ receipt: MutationReceipt) -> Bool {
        guard receipt.operationId == id, receipt.state == "accepted" else { return false }
        switch route {
        case .record:
            let wantedFollowUp = (try? WireJSON.decoder().decode(Payload.self, from: body))?.followUp
            return receipt.contact?.personId == personID && receipt.contact?.revision == 1
                && (wantedFollowUp == nil || receipt.followUp != nil)
                && (receipt.followUp == nil || receipt.followUp?.personId == personID)
        case .correction(let target):
            return receipt.contact?.personId == personID && receipt.contact?.id == target && receipt.contact?.revision == (expectedRevision ?? -1) + 1
        case .schedule: return receipt.followUp?.personId == personID && receipt.followUp?.revision == 0
        case .followUpChange(let target): return receipt.followUp?.personId == personID && receipt.followUp?.id == target && receipt.followUp?.revision == (expectedRevision ?? -1) + 1
        case .snooze: return receipt.snooze?.personId == personID && receipt.snooze?.revision == 0
        case .undoSnooze(let target): return receipt.snooze?.personId == personID && receipt.snooze?.id == target && receipt.snooze?.revision == (expectedRevision ?? -1) + 1 && receipt.snooze?.cancelledAt != nil
        }
    }
}

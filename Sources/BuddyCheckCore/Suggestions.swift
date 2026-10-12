import Foundation
import Observation

public struct SuggestionSnooze: Codable, Equatable, Sendable {
    public let personID: UUID
    public let until: Date
    public init(personID: UUID, until: Date) { self.personID = personID; self.until = until }
}

public enum SuggestionEligibility: Sendable { case available, assignedElsewhere, contactPaused, unavailable }
public enum MeetingPresence: Sendable { case present, absent, excused, notRecorded }
public struct MeetingEvidence: Sendable {
    public var date: Date
    public var presence: MeetingPresence
    public var complete: Bool
    public var generalMembership: Bool
    public init(date: Date, presence: MeetingPresence, complete: Bool, generalMembership: Bool = true) {
        self.date = date; self.presence = presence; self.complete = complete; self.generalMembership = generalMembership
    }
}

/// Minimal synthetic evidence; no notes, renewal fields or other callers' identities.
public struct SuggestionEvidence: Sendable {
    public var personID: UUID
    public var eligibility: SuggestionEligibility
    /// nil means unknown/partial history, never known empty history.
    public var historySince: Date?
    public var hasRecordedCheck: Bool
    public var lastAttempt: Date?
    public var lastConversation: Date?
    public var meetings: [MeetingEvidence]
    public init(personID: UUID, eligibility: SuggestionEligibility = .available, historySince: Date? = nil,
                hasRecordedCheck: Bool = false, lastAttempt: Date? = nil, lastConversation: Date? = nil,
                meetings: [MeetingEvidence] = []) {
        self.personID = personID; self.eligibility = eligibility; self.historySince = historySince
        self.hasRecordedCheck = hasRecordedCheck; self.lastAttempt = lastAttempt
        self.lastConversation = lastConversation; self.meetings = meetings
    }
}
public struct SuggestionBatch: Sendable {
    public var observedAt: Date
    public var validUntil: Date
    public var candidates: [SuggestionEvidence]
    public init(observedAt: Date, validUntil: Date, candidates: [SuggestionEvidence]) {
        self.observedAt = observedAt; self.validUntil = validUntil; self.candidates = candidates
    }
}
public enum SuggestionReason: Equatable, Sendable {
    case noChecks(since: Date), noConversation(since: Date), lastConversation(Date), absentMeetings([Date])
}
public struct MemberSuggestion: Equatable, Identifiable, Sendable {
    public var id: UUID { personID }
    public let personID: UUID
    public let reasons: [SuggestionReason]
    public let incompleteHistory: Bool
}
public enum SuggestionResult: Equatable, Sendable {
    case person(MemberSuggestion), exhausted, insufficientEvidence, none, stale, failed
}

public enum SuggestionEngine {
    public static let attemptDelay: TimeInterval = 7 * 24 * 60 * 60
    public static let conversationDelay: TimeInterval = 60 * 24 * 60 * 60

    /// Only the synthetic app uses client-side ranking. Connected ranking belongs on Rails.
    public static func evaluate(_ batch: SuggestionBatch, people: [Person], snapshot: LocalSnapshot,
                                skipped: Set<UUID>, now: Date) -> SuggestionResult {
        guard batch.observedAt <= now, batch.validUntil > now else { return .stale }
        guard Set(batch.candidates.map(\.personID)).count == batch.candidates.count else { return .failed }
        var ranked: [(suggestion: MemberSuggestion, group: Int, absence: Bool, waitSince: Date)] = []
        var incomplete = false
        for evidence in batch.candidates {
            guard people.contains(where: { $0.id == evidence.personID && $0.isSynthetic }),
                  evidence.eligibility == .available else { continue }
            let id = evidence.personID
            guard snapshot.draft?.personID != id,
                  !snapshot.followUps.contains(where: { $0.personID == id && $0.status == .open }),
                  !snapshot.suggestionSnoozes.contains(where: { $0.personID == id && $0.until > now }) else { continue }
            // Bad future evidence cannot become a known-empty record or an absence.
            let evidenceDates = [evidence.historySince, evidence.lastAttempt, evidence.lastConversation].compactMap { $0 }
            guard evidenceDates.allSatisfy({ $0 <= batch.observedAt }),
                  evidence.meetings.allSatisfy({ $0.date <= batch.observedAt }) else { incomplete = true; continue }
            let checks = snapshot.checks.filter { $0.personID == id }
            let attempt = (checks.filter { $0.outcome.countsAsAttempt }.map(\.occurredAt) + [evidence.lastAttempt, evidence.lastConversation].compactMap { $0 }).max()
            let conversation = (checks.filter { $0.outcome == .connected }.map(\.occurredAt) + [evidence.lastConversation].compactMap { $0 }).max()
            if let attempt, now.timeIntervalSince(attempt) < attemptDelay { continue }
            if let conversation, now.timeIntervalSince(conversation) < conversationDelay { continue }

            // Inspect the latest registers, not the latest two absent rows. A newer
            // incomplete/present/excused register must interrupt an absence streak.
            let latest = Array(evidence.meetings.sorted { $0.date > $1.date }.prefix(2))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Chicago")! // Synthetic Post meeting dates.
            let absent = latest.count == 2 && !calendar.isDate(latest[0].date, inSameDayAs: latest[1].date) && latest.allSatisfy {
                $0.generalMembership && $0.complete && $0.presence == .absent
            }
            var reasons: [SuggestionReason] = []
            let group: Int
            let waitSince: Date
            if let conversation {
                group = 2; waitSince = conversation; reasons.append(.lastConversation(conversation))
            } else if let since = evidence.historySince {
                let anyCheck = evidence.hasRecordedCheck || evidence.lastAttempt != nil || !checks.isEmpty
                group = anyCheck ? 1 : 0; waitSince = since
                reasons.append(anyCheck ? .noConversation(since: since) : .noChecks(since: since))
            } else { group = 3; waitSince = latest.last?.date ?? now }
            if absent { reasons.append(.absentMeetings(latest.map(\.date).sorted())) }
            guard !reasons.isEmpty else { incomplete = true; continue }
            ranked.append((MemberSuggestion(personID: id, reasons: reasons, incompleteHistory: evidence.historySince == nil), group, absent, waitSince))
        }
        ranked.sort {
            if $0.group != $1.group { return $0.group < $1.group }
            if $0.absence != $1.absence { return $0.absence }
            if $0.waitSince != $1.waitSince { return $0.waitSince < $1.waitSince }
            return $0.suggestion.personID.uuidString < $1.suggestion.personID.uuidString
        }
        if let next = ranked.first(where: { !skipped.contains($0.suggestion.personID) }) { return .person(next.suggestion) }
        if !ranked.isEmpty { return .exhausted }
        return incomplete ? .insufficientEvidence : .none
    }
}

@MainActor public protocol SuggestionSource {
    func load() throws -> SuggestionBatch
}

/// Fixed fictional history anchored at construction. Refresh never moves historical dates.
@MainActor public struct SyntheticSuggestionSource: SuggestionSource {
    private let anchor: Date
    private let now: () -> Date
    public init(now: @escaping () -> Date = Date.init) { self.now = now; anchor = now() }
    public func load() -> SuggestionBatch {
        func days(_ count: Int) -> Date { anchor.addingTimeInterval(-Double(count) * 86400) }
        let people = SyntheticDirectory.people
        return SuggestionBatch(observedAt: now(), validUntil: now().addingTimeInterval(15 * 60), candidates: [
            SuggestionEvidence(personID: people[0].id, historySince: days(180), hasRecordedCheck: true,
                               lastAttempt: days(90), lastConversation: days(90)),
            SuggestionEvidence(personID: people[1].id, historySince: days(180)),
            SuggestionEvidence(personID: people[2].id, meetings: [
                MeetingEvidence(date: days(65), presence: .absent, complete: true),
                MeetingEvidence(date: days(35), presence: .absent, complete: true)
            ])
        ])
    }
}

@MainActor @Observable public final class SuggestionSession {
    public private(set) var batch: SuggestionBatch?
    public private(set) var failed = false
    public private(set) var skipped: Set<UUID> = []
    @ObservationIgnored private let source: any SuggestionSource
    @ObservationIgnored private let now: () -> Date
    public init(source: any SuggestionSource, now: @escaping () -> Date = Date.init) { self.source = source; self.now = now }
    public func refresh() {
        do { batch = try source.load(); failed = false }
        catch { batch = nil; failed = true }
    }
    public func result(store: CheckStore) -> SuggestionResult {
        guard !failed, let batch else { return .failed }
        return SuggestionEngine.evaluate(batch, people: store.people, snapshot: store.snapshot, skipped: skipped, now: now())
    }
    public func skip(_ id: UUID) { skipped.insert(id) }
    public func startAgain() { skipped = []; refresh() }
    /// Recheck current source permission/evidence before leaving this attention surface.
    /// Selection changes no draft, check, follow-up or snooze.
    public func select(_ id: UUID, store: CheckStore) -> Bool {
        refresh()
        guard !failed, let batch else { return false }
        let others = Set(batch.candidates.map(\.personID)).subtracting([id])
        if case .person(let choice) = SuggestionEngine.evaluate(batch, people: store.people, snapshot: store.snapshot, skipped: others, now: now()) {
            return choice.personID == id
        }
        return false
    }
}

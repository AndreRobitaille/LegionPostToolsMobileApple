import Foundation
import Observation

@MainActor @Observable public final class CheckStore {
    public private(set) var snapshot = LocalSnapshot()
    public private(set) var loadError: String?
    public let people: [Person]
    @ObservationIgnored private let persistence: any SnapshotPersistence
    @ObservationIgnored private let now: () -> Date
    public var draft: CheckDraft? { snapshot.draft }
    public var checks: [BuddyCheck] { snapshot.checks.sorted { $0.occurredAt > $1.occurredAt } }
    public var followUps: [FollowUp] { snapshot.followUps.sorted { $0.due < $1.due } }

    public init(persistence: any SnapshotPersistence, people: [Person] = SyntheticDirectory.people,
                now: @escaping () -> Date = Date.init) {
        self.persistence = persistence; self.people = people; self.now = now
        reload()
    }
    public func reload() {
        do {
            snapshot = try persistence.load() ?? LocalSnapshot()
            loadError = nil
        } catch {
            loadError = (error as? WorkflowError)?.errorDescription ?? WorkflowError.storageNotReady.errorDescription
        }
    }
    public func person(_ id: UUID) -> Person? { people.first { $0.id == id } }
    public func check(_ id: UUID) -> BuddyCheck? { snapshot.checks.first { $0.id == id } }
    public func followUp(_ id: UUID) -> FollowUp? { snapshot.followUps.first { $0.id == id } }
    public func followUp(forCheck id: UUID) -> FollowUp? { snapshot.followUps.first { $0.checkID == id } }

    private func transaction(_ change: (inout LocalSnapshot) throws -> Void) throws {
        guard loadError == nil else { throw WorkflowError.storageNotReady }
        var candidate = snapshot
        try change(&candidate)
        try persistence.save(candidate)
        snapshot = candidate
    }

    @discardableResult public func begin(personID: UUID, origin: DraftOrigin, timeZone: String) throws -> UUID {
        guard person(personID) != nil else { throw WorkflowError.missingPerson }
        guard origin != .correction else { throw WorkflowError.missingCheck }
        let timestamp = now()
        let draft = CheckDraft(id: UUID(), personID: personID, origin: origin,
                               stage: origin == .manual ? .details : .outcome, method: .phone,
                               occurredAt: timestamp, eventTimeZone: timeZone, startedAt: timestamp)
        try transaction { state in
            guard state.draft == nil else { throw WorkflowError.unfinishedCheck }
            state.draft = draft
        }
        return draft.id
    }

    public func updateDraft(id: UUID, _ change: (inout CheckDraft) -> Void) throws {
        try transaction { state in
            guard var draft = state.draft, draft.id == id else { throw WorkflowError.missingDraft }
            change(&draft)
            state.draft = draft
        }
    }
    public func setMethod(id: UUID, method: ContactMethod) throws {
        try updateDraft(id: id) { draft in
            draft.method = method
            if let outcome = draft.outcome, !CheckOutcome.choices(for: method).contains(outcome) { draft.outcome = nil }
        }
    }
    public func finishDetails(id: UUID) throws {
        guard let draft, draft.id == id else { throw WorkflowError.missingDraft }
        guard draft.occurredAt <= now() else { throw WorkflowError.futureEvent }
        try updateDraft(id: id) { $0.stage = .outcome }
    }
    public func chooseReminder(id: UUID, timeZone: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: now())!
        let due = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextDay)!
        try updateDraft(id: id) {
            $0.followUpDue = $0.followUpDue ?? due
            $0.followUpTimeZone = $0.followUpTimeZone ?? timeZone
            $0.stage = .reminder
        }
    }
    public func discardDraft(id: UUID) throws {
        try transaction { state in
            guard state.draft?.id == id else { throw WorkflowError.missingDraft }
            state.draft = nil
        }
    }

    @discardableResult public func saveDraft(id: UUID, includeFollowUp: Bool) throws -> BuddyCheck {
        guard let draft, draft.id == id else {
            // Retry of an already committed operation, including after a restart.
            if let recorded = check(id) { return recorded }
            throw WorkflowError.missingDraft
        }
        guard person(draft.personID) != nil else { throw WorkflowError.missingPerson }
        guard let outcome = draft.outcome else { throw WorkflowError.missingOutcome }
        guard CheckOutcome.choices(for: draft.method).contains(outcome) else { throw WorkflowError.invalidOutcome }
        let timestamp = now()
        guard draft.occurredAt <= timestamp else { throw WorkflowError.futureEvent }
        if includeFollowUp && draft.origin != .correction {
            guard let due = draft.followUpDue, due > timestamp else { throw WorkflowError.pastReminder }
        }
        try transaction { state in
            if draft.origin == .correction {
                guard let index = state.checks.firstIndex(where: { $0.id == id }) else { throw WorkflowError.missingCheck }
                let old = state.checks[index]
                if old.outcome != outcome || old.method != draft.method || old.occurredAt != draft.occurredAt || old.eventTimeZone != draft.eventTimeZone {
                    state.checks[index].revisions.append(CheckRevision(changedAt: timestamp, previousMethod: old.method,
                        previousOutcome: old.outcome, previousOccurredAt: old.occurredAt, previousTimeZone: old.eventTimeZone))
                    state.checks[index].method = draft.method
                    state.checks[index].outcome = outcome
                    state.checks[index].occurredAt = draft.occurredAt
                    state.checks[index].eventTimeZone = draft.eventTimeZone
                    state.checks[index].updatedAt = timestamp
                }
            } else {
                guard !state.checks.contains(where: { $0.id == id }) else { throw WorkflowError.damagedStorage }
                state.checks.append(BuddyCheck(id: id, personID: draft.personID, method: draft.method,
                    outcome: outcome, occurredAt: draft.occurredAt, eventTimeZone: draft.eventTimeZone,
                    recordedAt: timestamp, updatedAt: timestamp, revisions: []))
                if includeFollowUp, let due = draft.followUpDue {
                    state.followUps.append(FollowUp(id: UUID(), checkID: id, personID: draft.personID, due: due,
                        timeZone: draft.followUpTimeZone ?? draft.eventTimeZone, status: .open))
                }
            }
            state.draft = nil
        }
        return check(id)!
    }

    public func beginCorrection(checkID: UUID) throws {
        guard let check = check(checkID) else { throw WorkflowError.missingCheck }
        guard person(check.personID) != nil else { throw WorkflowError.missingPerson }
        try transaction { state in
            guard state.draft == nil else { throw WorkflowError.unfinishedCheck }
            state.draft = CheckDraft(id: check.id, personID: check.personID, origin: .correction,
                stage: .outcome, method: check.method, occurredAt: check.occurredAt, eventTimeZone: check.eventTimeZone,
                outcome: check.outcome, startedAt: now())
        }
    }
    public func rescheduleFollowUp(id: UUID, due: Date, timeZone: String) throws {
        guard due > now() else { throw WorkflowError.pastReminder }
        try transaction { state in
            guard let index = state.followUps.firstIndex(where: { $0.id == id }) else { throw WorkflowError.missingFollowUp }
            guard state.followUps[index].status == .open else { throw WorkflowError.closedFollowUp }
            state.followUps[index].due = due; state.followUps[index].timeZone = timeZone
            state.reminderSnoozes[id] = nil
        }
    }
    public func closeFollowUp(id: UUID, status: FollowUpStatus) throws {
        guard status != .open else { throw WorkflowError.closedFollowUp }
        try transaction { state in
            guard let index = state.followUps.firstIndex(where: { $0.id == id }) else { throw WorkflowError.missingFollowUp }
            guard state.followUps[index].status == .open || state.followUps[index].status == status else { throw WorkflowError.closedFollowUp }
            state.followUps[index].status = status
            state.reminderIDs.removeAll { $0 == id }
            state.reminderSnoozes[id] = nil
        }
    }

    public func setDeviceReminder(id: UUID, enabled: Bool) throws {
        try transaction { state in
            guard let item = state.followUps.first(where: { $0.id == id }) else { throw WorkflowError.missingFollowUp }
            if enabled {
                guard item.status == .open else { throw WorkflowError.closedFollowUp }
                guard (state.reminderSnoozes[id] ?? item.due) > now() else { throw WorkflowError.pastReminder }
            }
            state.reminderIDs.removeAll { $0 == id }
            if enabled { state.reminderIDs.append(id) }
            else { state.reminderSnoozes[id] = nil }
        }
    }

    public func snoozeDeviceReminder(id: UUID, until: Date) throws {
        guard until.timeIntervalSince1970.isFinite, until > now() else { throw WorkflowError.pastReminder }
        try transaction { state in
            guard let item = state.followUps.first(where: { $0.id == id }) else { throw WorkflowError.missingFollowUp }
            guard item.status == .open else { throw WorkflowError.closedFollowUp }
            if !state.reminderIDs.contains(id) { state.reminderIDs.append(id) }
            state.reminderSnoozes[id] = until
        }
    }

    public func contactLink(for person: Person) -> ContactLink? {
        snapshot.contactLinks.first { $0.identity == ContactIdentity(person: person) }
    }
    public func beginContactCreation(person: Person, explicitlyCreateAnother: Bool = false) throws {
        let identity = ContactIdentity(person: person)
        try transaction { state in
            if let index = state.contactLinks.firstIndex(where: { $0.identity == identity }) {
                guard explicitlyCreateAnother else { throw ContactsError.creationUnresolved }
                state.contactLinks[index].creationPending = true
            } else {
                state.contactLinks.append(ContactLink(identity: identity, creationPending: true))
            }
        }
    }
    public func cancelContactCreation(person: Person) throws {
        let identity = ContactIdentity(person: person)
        try transaction { state in
            guard let index = state.contactLinks.firstIndex(where: { $0.identity == identity }), state.contactLinks[index].creationPending else { return }
            if state.contactLinks[index].contactID == nil { state.contactLinks.remove(at: index) }
            else { state.contactLinks[index].creationPending = false }
        }
    }
    public func rememberContact(person: Person, contactID: String, managed: ManagedContactFields) throws {
        guard !contactID.isEmpty else { throw ContactsError.emptyIdentifier }
        let identity = ContactIdentity(person: person)
        try transaction { state in
            let link = ContactLink(identity: identity, contactID: contactID, managed: managed)
            if let index = state.contactLinks.firstIndex(where: { $0.identity == identity }) { state.contactLinks[index] = link }
            else { state.contactLinks.append(link) }
        }
    }

    public func snoozeSuggestion(personID: UUID) throws {
        guard person(personID)?.isSynthetic == true else { throw WorkflowError.missingPerson }
        let until = now().addingTimeInterval(SuggestionEngine.attemptDelay)
        try transaction { state in
            state.suggestionSnoozes.removeAll { $0.personID == personID || $0.until <= now() }
            state.suggestionSnoozes.append(SuggestionSnooze(personID: personID, until: until))
        }
    }
    public func showSuggestionAgain(personID: UUID) throws {
        try transaction { state in state.suggestionSnoozes.removeAll { $0.personID == personID } }
    }

}

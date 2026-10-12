import Foundation
import Observation
import BuddyCheckCore

public struct ConnectedReminderIntent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let followUpID: Int
    public let due: Date
    public let revision: Int
    public let snoozedUntil: Date?
    public init(record: FollowUpRecord, id: UUID = UUID(), snoozedUntil: Date? = nil) throws {
        guard record.id > 0, record.personId > 0, record.revision >= 0,
              record.dueAt.timeIntervalSince1970.isFinite, TimeZone(identifier: record.entryZone) != nil,
              snoozedUntil.map({ $0.timeIntervalSince1970.isFinite }) ?? true
        else { throw ClientError.invalidResponse }
        self.id = id; followUpID = record.id; revision = record.revision
        due = DeviceReminder(id: id, due: record.dueAt).due
        self.snoozedUntil = snoozedUntil.map { DeviceReminder(id: id, due: $0).due }
    }
    public var deviceReminder: DeviceReminder { DeviceReminder(id: id, due: snoozedUntil ?? due) }
    public func refreshed(record: FollowUpRecord) throws -> ConnectedReminderIntent {
        try ConnectedReminderIntent(record: record, id: id,
                                    snoozedUntil: DeviceReminder(id: id, due: record.dueAt).due == due ? snoozedUntil : nil)
    }
}

public struct ConnectedReminderDestination: Sendable {
    public let record: FollowUpRecord
    public let changed: Bool
}

/// Keeps only notification status in memory. Displayed Post records always come
/// from fresh account-authorized reads; persisted intent holds no contact fields.
@MainActor @Observable public final class ConnectedReminders {
    public let namespace: String
    public private(set) var states: [Int: DeviceReminderStatus] = [:]
    public private(set) var removalUnconfirmed = false
    public private(set) var busy = false
    @ObservationIgnored private weak var account: ConnectedAccount?
    @ObservationIgnored private let scheduler: any ReminderScheduling
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var again = false
    @ObservationIgnored private var adding: Task<Void, Error>?

    init(account: ConnectedAccount, scope: AccountScope, scheduler: any ReminderScheduling,
         now: @escaping () -> Date = Date.init) {
        self.account = account; namespace = scope.reminderNamespace
        self.scheduler = scheduler; self.now = now
    }
    private var journal: SubmissionJournal? {
        guard !invalidated, let account, account.session != nil,
              let journal = account.journal, journal.snapshot.scope.reminderNamespace == namespace else { return nil }
        return journal
    }
    public func status(_ followUpID: Int) -> DeviceReminderStatus {
        if let state = states[followUpID] { return state }
        if journal?.snapshot.phoneReminders?[followUpID] != nil { return .checking }
        return removalUnconfirmed ? .removalUnconfirmed : .off
    }
    public func snoozedUntil(_ id: Int) -> Date? { journal?.snapshot.phoneReminders?[id]?.snoozedUntil }
    private func current(_ id: Int, minimumRevision: Int = 0) async throws -> (record: FollowUpRecord, person: PersonCardResponse) {
        guard let account, journal != nil else { throw ClientError.journalUnavailable }
        return try await account.perform({ client, token in
            let record = try await client.followUp(id: id, token: token)
            guard record.revision >= minimumRevision else { throw ClientError.invalidResponse }
            let person = try await client.person(record.personId, token: token)
            return (record, person)
        }, now: now())
    }
    public func setEnabled(_ enabled: Bool, followUpID: Int) async throws {
        guard let journal else { throw ClientError.journalUnavailable }
        if enabled {
            let existing = journal.snapshot.phoneReminders?[followUpID]
            let record = try await current(followUpID, minimumRevision: existing?.revision ?? 0).record
            guard self.journal === journal, journal.snapshot.phoneReminders?[followUpID] == existing else { throw CancellationError() }
            let intent = try existing?.refreshed(record: record) ?? ConnectedReminderIntent(record: record)
            guard record.status == .open, intent.deviceReminder.due > now() else { throw ClientError.invalidInput }
            // A failed disk write must not prompt or schedule anything.
            try journal.rememberReminder(intent)
            states[followUpID] = .checking
            if await scheduler.authorization() == .notDetermined {
                guard self.journal === journal else { throw CancellationError() }
                do { try await scheduler.requestAuthorization() }
                catch { states[followUpID] = .unavailable; return }
            }
        } else {
            try journal.removeReminder(followUpID: followUpID)
            states[followUpID] = .checking
        }
        await refresh()
    }
    public func snooze(followUpID: Int, until: Date) async throws {
        guard until.timeIntervalSince1970.isFinite, until > now() else { throw ClientError.invalidInput }
        guard let journal else { throw ClientError.journalUnavailable }
        let existing = journal.snapshot.phoneReminders?[followUpID]
        let record = try await current(followUpID, minimumRevision: existing?.revision ?? 0).record
        guard self.journal === journal, journal.snapshot.phoneReminders?[followUpID] == existing else { throw CancellationError() }
        guard record.status == .open else { throw ClientError.invalidInput }
        try journal.rememberReminder(ConnectedReminderIntent(record: record, id: existing?.id ?? UUID(), snoozedUntil: until))
        states[followUpID] = .checking
        if await scheduler.authorization() == .notDetermined {
            guard self.journal === journal else { throw CancellationError() }
            do { try await scheduler.requestAuthorization() }
            catch { states[followUpID] = .unavailable; return }
        }
        await refresh()
    }
    public func refresh() async {
        // SwiftUI cancels a view's task when a permission prompt or navigation
        // replaces that view. The persisted choice belongs to the account;
        // account lock/invalidation, not view lifetime, controls reconciliation.
        let task = Task { @MainActor [weak self] in await self?.reconcile() }
        await task.value
    }
    private func reconcile() async {
        again = true
        guard !busy, !invalidated else { return }
        busy = true
        defer { busy = false }
        repeat {
            again = false
            guard let journal else { return }
            let original = journal.snapshot.phoneReminders ?? [:]
            let permission = await scheduler.authorization()
            guard self.journal === journal else { return }
            if permission != .allowed {
                removalUnconfirmed = !(await scheduler.removeAll())
                guard self.journal === journal else { return }
                states = original.mapValues { _ in removalUnconfirmed ? .removalUnconfirmed : (permission == .denied ? .denied : .needsPermission) }
                if original != (journal.snapshot.phoneReminders ?? [:]) { again = true }
                continue
            }
            let pending = await scheduler.pending(); let delivered = await scheduler.delivered()
            guard self.journal === journal else { return }
            let ownedIDs = Set(original.values.map(\.id))
            let orphans = Set((pending + delivered).map(\.id)).subtracting(ownedIDs)
            await scheduler.remove(Array(orphans))
            guard self.journal === journal else { return }
            var next: [Int: DeviceReminderStatus] = [:]
            var verifiedRequests: [Int: DeviceReminder] = [:]
            var selected = 0
            for intent in original.values.sorted(by: { $0.deviceReminder.due == $1.deviceReminder.due ? $0.followUpID < $1.followUpID : $0.deviceReminder.due < $1.deviceReminder.due }) {
                guard self.journal === journal else { return }
                // Turning an opt-in off during a suspended refresh must win.
                guard journal.snapshot.phoneReminders?[intent.followUpID] == intent else { again = true; continue }
                do {
                    let current = try await current(intent.followUpID, minimumRevision: intent.revision)
                    let record = current.record
                    guard self.journal === journal else { return }
                    guard journal.snapshot.phoneReminders?[intent.followUpID] == intent else { again = true; continue }
                    if record.status != .open {
                        try journal.removeReminder(followUpID: intent.followUpID)
                        await scheduler.remove([intent.id]); next[intent.followUpID] = .off
                        continue
                    }
                    let updated = try intent.refreshed(record: record)
                    try journal.rememberReminder(updated)
                    let request = DeviceReminder(id: updated.id, due: updated.deviceReminder.due,
                                                 body: ReminderMessage.body(firstName: current.person.firstName))
                    verifiedRequests[intent.followUpID] = request
                    let stale = (pending + delivered).contains(where: { $0.id == intent.id && $0 != request })
                    if stale {
                        await scheduler.remove([intent.id])
                    }
                    guard self.journal === journal,
                          journal.snapshot.phoneReminders?[intent.followUpID] == updated else { again = true; continue }
                    if request.due <= now() { next[intent.followUpID] = .due; continue }
                    selected += 1
                    if selected > 50 {
                        await scheduler.remove([intent.id]); next[intent.followUpID] = .waiting; continue
                    }
                    if !pending.contains(request) || stale {
                        let task = Task { @MainActor [scheduler, weak self] in
                            guard let self, self.journal === journal else { throw CancellationError() }
                            try await scheduler.schedule(request)
                        }
                        adding = task
                        do { try await task.value } catch { next[intent.followUpID] = .unavailable }
                        adding = nil
                    }
                } catch {
                    guard self.journal === journal else { return }
                    if case ClientError.server(let status, _) = error, status == 404 || status == 403 {
                        do { try journal.removeReminder(followUpID: intent.followUpID) }
                        catch { next[intent.followUpID] = .unavailable; continue }
                        await scheduler.remove([intent.id]); next[intent.followUpID] = .off
                    } else {
                        // Uncertain network/expiry cannot authorize a new alert,
                        // and does not silently erase the caller's previous choice.
                        next[intent.followUpID] = .unavailable
                    }
                }
            }
            guard self.journal === journal else { return }
            let confirmed = await scheduler.pending(); let shown = await scheduler.delivered()
            guard self.journal === journal else { return }
            let desired = journal.snapshot.phoneReminders ?? [:]
            let desiredIDs = Set(desired.values.map(\.id))
            removalUnconfirmed = (confirmed + shown).contains { !desiredIDs.contains($0.id) }
            for id in desired.keys where next[id] == nil {
                next[id] = verifiedRequests[id].map { confirmed.contains($0) } == true ? .scheduled : .unavailable
            }
            for id in Set(states.keys).union(original.keys) where desired[id] == nil {
                next[id] = removalUnconfirmed ? .removalUnconfirmed : .off
            }
            states = next
            if original != desired { again = true }
        } while again && !invalidated
    }
    public func resolve(namespace: String, reminder: DeviceReminder) async throws -> ConnectedReminderDestination {
        guard namespace == self.namespace else { throw ClientError.accountMismatch }
        guard let journal, let intent = journal.snapshot.phoneReminders?.values.first(where: { $0.id == reminder.id })
        else { throw ClientError.server(status: 404, code: "not_found") }
        let record = try await current(intent.followUpID, minimumRevision: intent.revision).record
        guard self.journal === journal, journal.snapshot.phoneReminders?[intent.followUpID]?.id == reminder.id else { throw CancellationError() }
        let currentSchedule = try intent.refreshed(record: record).deviceReminder
        return ConnectedReminderDestination(record: record, changed: record.status != .open || !currentSchedule.hasSameSchedule(as: reminder))
    }
    /// Invalidation precedes the wait, so no later refresh can enqueue an add.
    /// Waiting only on the OS add avoids deadlocking a revocation received by a
    /// Post read inside this coordinator's own refresh.
    func purge() async -> Bool {
        invalidated = true; again = false; states = [:]
        if let adding { _ = try? await adding.value }
        removalUnconfirmed = !(await scheduler.removeAll())
        return !removalUnconfirmed
    }
}

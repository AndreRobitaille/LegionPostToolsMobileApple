import Foundation
import Observation

public enum ReminderAuthorization: Sendable { case notDetermined, allowed, denied }
public enum ReminderSnoozeChoice: String, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes, oneHour, tomorrowMorning
    public var id: Self { self }
    public var label: String {
        switch self { case .fifteenMinutes: "15 minutes"; case .oneHour: "1 hour"; case .tomorrowMorning: "Tomorrow at 9 AM" }
    }
    public func due(after now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .fifteenMinutes: return now.addingTimeInterval(15 * 60)
        case .oneHour: return now.addingTimeInterval(60 * 60)
        case .tomorrowMorning:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
    }
}
public enum ReminderMessage {
    public static func body(firstName: String, method: ContactMethod? = nil) -> String {
        let name = firstName.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !name.isEmpty else { return "Follow up on your Buddy Check." }
        let action: String
        switch method { case .phone: action = "Call"; case .text: action = "Text"; case .visit: action = "Visit"; case nil: action = "Check in with" }
        return "\(action) \(name) for a Buddy Check"
    }
}
public struct DeviceReminder: Equatable, Sendable {
    public let id: UUID
    public let due: Date
    public let body: String
    public init(id: UUID, due: Date, body: String = "Follow up on your Buddy Check.") {
        self.id = id
        self.due = Date(timeIntervalSince1970: floor(due.timeIntervalSince1970))
        self.body = body
    }
    public func hasSameSchedule(as other: DeviceReminder) -> Bool {
        id == other.id && due == other.due
    }
    public var utcComponents: DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var value = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
        value.calendar = calendar; value.timeZone = calendar.timeZone
        return value
    }
}

/// Implementations own one opaque store namespace and must preserve other stores' requests.
@MainActor public protocol ReminderScheduling {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async throws
    func pending() async -> [DeviceReminder]
    func delivered() async -> [DeviceReminder]
    func schedule(_ reminder: DeviceReminder) async throws
    func remove(_ ids: [UUID]) async
    func removeAll() async -> Bool
}

extension ReminderScheduling {
    public func removeAll() async -> Bool {
        let pending = await pending(); let delivered = await delivered()
        await remove(Array(Set((pending + delivered).map(\.id))))
        let remaining = await self.pending(); let shown = await self.delivered()
        return remaining.isEmpty && shown.isEmpty
    }
}

public enum DeviceReminderStatus: Equatable, Sendable {
    case off, scheduled, due, denied, needsPermission, unavailable, removalUnconfirmed, waiting, checking
    public var label: String {
        switch self {
        case .off: "No phone alert is scheduled."
        case .scheduled: "Reminder scheduled on this iPhone."
        case .due: "The reminder time has passed. Your follow-up is still open."
        case .denied: "Notifications are off. Your follow-up is saved in the app."
        case .needsPermission: "Allow notifications to schedule a phone reminder."
        case .unavailable: "The phone reminder could not be confirmed. Your follow-up is saved."
        case .removalUnconfirmed: "The phone reminder may still be scheduled. Try dismissing it again."
        case .waiting: "This reminder is not scheduled yet. Earlier reminders fill the available space."
        case .checking: "Checking phone reminder…"
        }
    }
}

@MainActor @Observable public final class DeviceReminders {
    public private(set) var states: [UUID: DeviceReminderStatus] = [:]
    public private(set) var busy = false
    @ObservationIgnored private let store: CheckStore
    @ObservationIgnored private let scheduler: any ReminderScheduling
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var again = false
    public init(store: CheckStore, scheduler: any ReminderScheduling, now: @escaping () -> Date = Date.init) {
        self.store = store; self.scheduler = scheduler; self.now = now
    }
    public func status(_ id: UUID) -> DeviceReminderStatus {
        guard store.followUp(id)?.status == .open else { return .off }
        return states[id] ?? (store.snapshot.reminderIDs.contains(id) ? .checking : .off)
    }
    public func setEnabled(_ enabled: Bool, id: UUID) async throws {
        // Failed persistence must not schedule, remove, or prompt for anything.
        try store.setDeviceReminder(id: id, enabled: enabled)
        states[id] = .checking
        if enabled, await scheduler.authorization() == .notDetermined {
            do { try await scheduler.requestAuthorization() }
            catch { states[id] = .unavailable; return }
        }
        await refresh()
    }
    public func snooze(id: UUID, until: Date) async throws {
        try store.snoozeDeviceReminder(id: id, until: until)
        states[id] = .checking
        if await scheduler.authorization() == .notDetermined {
            do { try await scheduler.requestAuthorization() }
            catch { states[id] = .unavailable; return }
        }
        await refresh()
    }
    public func snoozedUntil(_ id: UUID) -> Date? { store.snapshot.reminderSnoozes[id] }
    private func request(for item: FollowUp, snapshot: LocalSnapshot) -> DeviceReminder {
        let person = store.person(item.personID)
        let method = snapshot.checks.first { $0.id == item.checkID }?.method
        return DeviceReminder(id: item.id, due: snapshot.reminderSnoozes[item.id] ?? item.due,
                              body: ReminderMessage.body(firstName: person?.firstName ?? "", method: method))
    }
    public func refresh() async {
        again = true
        guard !busy else { return }
        busy = true
        defer { busy = false }
        repeat {
            again = false
            guard store.loadError == nil else { states = [:]; return }
            let permission = await scheduler.authorization()
            let pending = await scheduler.pending()
            let delivered = await scheduler.delivered()
            let snapshot = store.snapshot
            let desired = snapshot.followUps.filter { snapshot.reminderIDs.contains($0.id) && $0.status == .open }
            let current = Dictionary(uniqueKeysWithValues: desired.map { ($0.id, request(for: $0, snapshot: snapshot)) })
            // Remove stale delivered copies as well as pending requests, including old due times.
            let stale = (pending + delivered).filter {
                permission != .allowed || current[$0.id] != $0
            }.map(\.id)
            await scheduler.remove(Array(Set(stale)))
            let future = current.values.filter { $0.due > now() }.sorted {
                $0.due == $1.due ? $0.id.uuidString < $1.id.uuidString : $0.due < $1.due
            }
            // Bounded queue, with an explicit unscheduled state for overflow.
            let selected = Set(future.prefix(50).map(\.id))
            var next: [UUID: DeviceReminderStatus] = [:]
            for item in desired {
                if permission != .allowed {
                    next[item.id] = permission == .denied ? .denied : .needsPermission
                } else if let request = current[item.id], request.due <= now() {
                    next[item.id] = .due
                } else if !selected.contains(item.id) {
                    next[item.id] = .waiting
                    await scheduler.remove([item.id])
                } else {
                    let request = current[item.id]!
                    if !pending.contains(request) || stale.contains(item.id) {
                        do { try await scheduler.schedule(request) }
                        catch { next[item.id] = .unavailable }
                    }
                }
            }
            let confirmed = await scheduler.pending()
            let remainingDelivered = await scheduler.delivered()
            for item in desired where next[item.id] == nil {
                next[item.id] = current[item.id].map { confirmed.contains($0) } == true ? .scheduled : .unavailable
            }
            for item in snapshot.followUps where current[item.id] == nil {
                next[item.id] = (confirmed + remainingDelivered).contains { $0.id == item.id } ? .removalUnconfirmed : .off
            }
            states = next
            // A close/reschedule during any suspension must win over a late add.
            if snapshot != store.snapshot { again = true }
        } while again
    }
    public func resolve(_ reminder: DeviceReminder) -> ReminderDestination {
        guard store.loadError == nil else { return .storageUnavailable }
        guard let item = store.followUp(reminder.id) else { return .missing }
        return .followUp(id: item.id, changed: item.status != .open || !request(for: item, snapshot: store.snapshot).hasSameSchedule(as: reminder))
    }
}

public enum ReminderDestination: Equatable {
    case storageUnavailable, missing, followUp(id: UUID, changed: Bool)
}

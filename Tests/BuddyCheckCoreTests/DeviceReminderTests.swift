import Foundation
import Testing
@testable import BuddyCheckCore

@MainActor private final class ReminderMemory: SnapshotPersistence {
    var snapshot: LocalSnapshot?
    var fail = false
    func load() throws -> LocalSnapshot? { snapshot }
    func save(_ value: LocalSnapshot) throws {
        if fail { throw CocoaError(.fileWriteOutOfSpace) }
        snapshot = value
    }
}
@MainActor private final class ReminderFake: ReminderScheduling {
    var permission = ReminderAuthorization.allowed
    var grant = false
    var promptCount = 0
    var requests: [DeviceReminder] = []
    var deliveredRequests: [DeviceReminder] = []
    var scheduled: [DeviceReminder] = []
    var fail = false
    var ignoreRemoval = false
    var duringSchedule: (() -> Void)?
    func authorization() async -> ReminderAuthorization { permission }
    func requestAuthorization() async throws { promptCount += 1; permission = grant ? .allowed : .denied }
    func pending() async -> [DeviceReminder] { requests }
    func delivered() async -> [DeviceReminder] { deliveredRequests }
    func schedule(_ reminder: DeviceReminder) async throws {
        if fail { throw CocoaError(.fileWriteUnknown) }
        duringSchedule?(); duringSchedule = nil
        requests.removeAll { $0.id == reminder.id }; requests.append(reminder)
        scheduled.append(reminder)
    }
    func remove(_ ids: [UUID]) async {
        if ignoreRemoval { return }
        requests.removeAll { ids.contains($0.id) }; deliveredRequests.removeAll { ids.contains($0.id) }
    }
}

@Suite @MainActor struct DeviceReminderTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func setup() throws -> (CheckStore, ReminderMemory, ReminderFake, DeviceReminders, FollowUp) {
        let memory = ReminderMemory()
        let store = CheckStore(persistence: memory, now: { now })
        let id = try store.begin(personID: SyntheticDirectory.people[0].id, origin: .manual, timeZone: "America/Chicago")
        try store.updateDraft(id: id) { $0.outcome = .noAnswer; $0.followUpDue = now.addingTimeInterval(3600); $0.followUpTimeZone = "America/Chicago" }
        try store.saveDraft(id: id, includeFollowUp: true)
        let fake = ReminderFake()
        let service = DeviceReminders(store: store, scheduler: fake, now: { now })
        return (store, memory, fake, service, try #require(store.followUps.first))
    }
    @Test func permissionIsRequestedOnlyForExplicitOptInAndDenialKeepsWork() async throws {
        let (store, _, fake, service, item) = try setup()
        fake.permission = .notDetermined
        await service.refresh()
        #expect(fake.promptCount == 0); #expect(fake.requests.isEmpty)
        try await service.setEnabled(true, id: item.id)
        #expect(fake.promptCount == 1); #expect(service.status(item.id) == .denied)
        #expect(store.followUp(item.id) == item); #expect(store.checks.count == 1)
        await service.refresh()
        #expect(fake.promptCount == 1)
        fake.permission = .allowed
        await service.refresh()
        #expect(service.status(item.id) == .scheduled)
        fake.permission = .denied
        await service.refresh()
        #expect(fake.requests.isEmpty); #expect(service.status(item.id) == .denied)
    }
    @Test func failedIntentWriteCannotScheduleOrRequestPermission() async throws {
        let (store, memory, fake, service, item) = try setup()
        memory.fail = true; fake.permission = .notDetermined
        await #expect(throws: CocoaError.self) { try await service.setEnabled(true, id: item.id) }
        #expect(store.snapshot.reminderIDs.isEmpty); #expect(fake.promptCount == 0); #expect(fake.requests.isEmpty)
    }
    @Test func restartRepairsSavedIntentAndRepeatedRefreshDoesNotReschedule() async throws {
        let (store, memory, fake, _, item) = try setup()
        try store.setDeviceReminder(id: item.id, enabled: true)
        let reopened = CheckStore(persistence: memory, now: { now })
        let service = DeviceReminders(store: reopened, scheduler: fake, now: { now })
        await service.refresh(); await service.refresh()
        #expect(service.status(item.id) == .scheduled); #expect(fake.scheduled.count == 1)
        #expect(fake.requests.count == 1)
    }
    @Test func rescheduleReplacesPendingAndDeliveredWithoutChangingChecks() async throws {
        let (store, _, fake, service, item) = try setup()
        try await service.setEnabled(true, id: item.id)
        let original = try #require(fake.requests.first)
        fake.deliveredRequests = [original]
        try store.rescheduleFollowUp(id: item.id, due: item.due.addingTimeInterval(600), timeZone: "Asia/Tokyo")
        await service.refresh()
        #expect(fake.deliveredRequests.isEmpty)
        #expect(fake.requests == [DeviceReminder(id: item.id, due: item.due.addingTimeInterval(600), body: "Call Robert for a Buddy Check")])
        #expect(service.resolve(original) == .followUp(id: item.id, changed: true))
        #expect(store.checks.count == 1); #expect(store.draft == nil)
    }
    @Test(arguments: [FollowUpStatus.completed, .cancelled])
    func closingRemovesAlertsAndStaleTapDoesNotReopen(_ status: FollowUpStatus) async throws {
        let (store, _, fake, service, item) = try setup()
        try await service.setEnabled(true, id: item.id)
        fake.deliveredRequests = fake.requests
        try store.closeFollowUp(id: item.id, status: status)
        await service.refresh()
        #expect(fake.requests.isEmpty); #expect(fake.deliveredRequests.isEmpty)
        #expect(store.snapshot.reminderIDs.isEmpty)
        #expect(service.resolve(DeviceReminder(id: item.id, due: item.due)) == .followUp(id: item.id, changed: true))
        #expect(store.followUp(item.id)?.status == status); #expect(store.checks.count == 1)
    }
    @Test func closeDuringScheduleWinsOverLateSystemAdd() async throws {
        let (store, _, fake, service, item) = try setup()
        fake.duringSchedule = { try! store.closeFollowUp(id: item.id, status: .completed) }
        try await service.setEnabled(true, id: item.id)
        #expect(fake.requests.isEmpty); #expect(service.status(item.id) == .off)
    }
    @Test func scheduleFailureIsNotClaimedAsScheduledAndRetryUsesSameID() async throws {
        let (_, _, fake, service, item) = try setup()
        fake.fail = true
        try await service.setEnabled(true, id: item.id)
        #expect(service.status(item.id) == .unavailable)
        fake.fail = false; await service.refresh()
        #expect(fake.requests.map(\.id) == [item.id]); #expect(service.status(item.id) == .scheduled)
        try await service.setEnabled(false, id: item.id)
        #expect(fake.requests.isEmpty); #expect(service.status(item.id) == .off)
    }
    @Test func dueDoesNotClaimDeliveryAndMissingLinkCannotCreateWork() async throws {
        let (store, _, fake, service, item) = try setup()
        try store.setDeviceReminder(id: item.id, enabled: true)
        let later = DeviceReminders(store: store, scheduler: fake, now: { item.due.addingTimeInterval(60) })
        await later.refresh()
        #expect(later.status(item.id) == .due); #expect(fake.requests.isEmpty)
        #expect(service.resolve(DeviceReminder(id: UUID(), due: item.due)) == .missing)
        #expect(store.followUp(item.id)?.status == .open); #expect(store.draft == nil)
    }
    @Test func unconfirmedRemovalRetainsRetryWithoutClaimingAlertIsOff() async throws {
        let (_, _, fake, service, item) = try setup()
        try await service.setEnabled(true, id: item.id)
        fake.ignoreRemoval = true
        try await service.setEnabled(false, id: item.id)
        #expect(service.status(item.id) == .removalUnconfirmed)
        fake.ignoreRemoval = false
        try await service.setEnabled(false, id: item.id)
        #expect(service.status(item.id) == .off); #expect(fake.requests.isEmpty)
    }
    @Test func utcTriggerStaysAtSameInstantAcrossTravelAndDST() {
        for stamp in [1_793_511_000.0, 1_805_000_000.75] {
            let value = DeviceReminder(id: UUID(), due: Date(timeIntervalSince1970: stamp))
            let components = value.utcComponents
            #expect(components.timeZone?.secondsFromGMT() == 0)
            var calendar = Calendar(identifier: .gregorian)
            for zone in ["America/Chicago", "Asia/Tokyo", "Pacific/Honolulu"] {
                calendar.timeZone = TimeZone(identifier: zone)!
                #expect(calendar.date(from: components) == value.due)
            }
        }
    }
    @Test func queueOverflowIsExplicitAndClosingEarlierWorkPromotesNextReminder() async throws {
        let (store, _, fake, service, first) = try setup()
        try store.setDeviceReminder(id: first.id, enabled: true)
        for offset in 1...50 {
            let id = try store.begin(personID: first.personID, origin: .manual, timeZone: "America/Chicago")
            try store.updateDraft(id: id) {
                $0.outcome = .notAttempted; $0.followUpDue = first.due.addingTimeInterval(Double(offset))
            }
            try store.saveDraft(id: id, includeFollowUp: true)
            try store.setDeviceReminder(id: #require(store.followUp(forCheck: id)).id, enabled: true)
        }
        let last = try #require(store.followUps.last)
        await service.refresh()
        #expect(fake.requests.count == 50); #expect(service.status(last.id) == .waiting)
        try store.closeFollowUp(id: first.id, status: .cancelled)
        await service.refresh()
        #expect(fake.requests.count == 50); #expect(service.status(last.id) == .scheduled)
        #expect(!fake.requests.contains { $0.id == first.id })
    }
    @Test func versionThreeMigratesWithoutOptingInAndVersionFourRestoresIntent() throws {
        let (store, _, _, _, item) = try setup()
        let encoder = JSONEncoder(); let decoder = JSONDecoder()
        var old = try #require(JSONSerialization.jsonObject(with: encoder.encode(store.snapshot)) as? [String: Any])
        old["formatVersion"] = 3; old.removeValue(forKey: "reminderIDs")
        let migrated = try decoder.decode(LocalSnapshot.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(migrated.followUps == store.snapshot.followUps); #expect(migrated.checks == store.checks)
        #expect(migrated.reminderIDs.isEmpty); #expect(migrated.formatVersion == 5)
        try store.setDeviceReminder(id: item.id, enabled: true)
        let restored = try decoder.decode(LocalSnapshot.self, from: encoder.encode(store.snapshot))
        #expect(restored.reminderIDs == [item.id])
    }

    @Test func snoozeDueReminderKeepsWorkAndRestoresThenDismissesTheSameAlert() async throws {
        var clock = now
        let memory = ReminderMemory()
        let store = CheckStore(persistence: memory, now: { clock })
        let checkID = try store.begin(personID: SyntheticDirectory.people[0].id, origin: .manual, timeZone: "America/Chicago")
        try store.updateDraft(id: checkID) { $0.outcome = .notAttempted; $0.followUpDue = clock.addingTimeInterval(60) }
        try store.saveDraft(id: checkID, includeFollowUp: true)
        let item = try #require(store.followUps.first); let check = store.checks
        let fake = ReminderFake(); let service = DeviceReminders(store: store, scheduler: fake, now: { clock })
        try await service.setEnabled(true, id: item.id)
        let original = try #require(fake.requests.first)
        #expect(original.body == "Call Robert for a Buddy Check")
        clock = clock.addingTimeInterval(65); fake.deliveredRequests = [original]; fake.requests = []
        let until = clock.addingTimeInterval(900)
        try await service.snooze(id: item.id, until: until)
        #expect(fake.requests.count == 1 && fake.requests.first?.id == item.id && fake.requests.first?.due == until)
        #expect(fake.deliveredRequests.isEmpty && store.followUp(item.id) == item && store.checks == check)
        let snoozed = try #require(fake.requests.first)
        #expect(service.resolve(snoozed) == .followUp(id: item.id, changed: false))
        #expect(service.resolve(original) == .followUp(id: item.id, changed: true))
        let reopened = CheckStore(persistence: memory, now: { clock })
        let restored = DeviceReminders(store: reopened, scheduler: fake, now: { clock })
        let adds = fake.scheduled.count; await restored.refresh()
        #expect(fake.scheduled.count == adds && restored.snoozedUntil(item.id) == until)
        try await restored.snooze(id: item.id, until: until.addingTimeInterval(3600))
        #expect(fake.requests.count == 1 && fake.requests.first?.id == original.id)
        try await restored.setEnabled(false, id: item.id)
        #expect(fake.requests.isEmpty && fake.deliveredRequests.isEmpty)
        #expect(reopened.snapshot.reminderSnoozes.isEmpty && reopened.snapshot.reminderIDs.isEmpty)
        #expect(reopened.checks == check && reopened.followUp(item.id) == item)
    }

    @Test func snoozePersistenceFailureAndClosingDuringAddPreserveTruthfulState() async throws {
        let (store, memory, fake, service, item) = try setup()
        try await service.setEnabled(true, id: item.id)
        let original = fake.requests; let snapshot = store.snapshot
        memory.fail = true
        await #expect(throws: CocoaError.self) { try await service.snooze(id: item.id, until: now.addingTimeInterval(900)) }
        #expect(fake.requests == original && store.snapshot == snapshot)
        memory.fail = false
        fake.duringSchedule = { try! store.closeFollowUp(id: item.id, status: .completed) }
        try await service.snooze(id: item.id, until: now.addingTimeInterval(900))
        #expect(fake.requests.isEmpty && store.snapshot.reminderSnoozes.isEmpty && store.checks.count == 1)
    }

    @Test func actualFollowUpRescheduleClearsOnlyItsSnooze() async throws {
        let (store, _, fake, service, item) = try setup()
        try await service.snooze(id: item.id, until: now.addingTimeInterval(900))
        let changed = now.addingTimeInterval(7200)
        try store.rescheduleFollowUp(id: item.id, due: changed, timeZone: "America/Chicago")
        await service.refresh()
        #expect(service.snoozedUntil(item.id) == nil && fake.requests.first?.due == changed)
        #expect(store.checks.count == 1 && store.followUp(item.id)?.status == .open)
    }

    @Test func versionFourMigratesAndSnoozeSurvivesJSONStorage() throws {
        let (store, _, _, _, item) = try setup()
        try store.setDeviceReminder(id: item.id, enabled: true)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = JSONSnapshotPersistence(fileURL: folder.appendingPathComponent("snapshot.json"))
        try disk.save(store.snapshot)
        var old = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: disk.fileURL)) as? [String: Any])
        old["formatVersion"] = 4; old.removeValue(forKey: "reminderSnoozes")
        try JSONSerialization.data(withJSONObject: old).write(to: disk.fileURL)
        let loaded = try disk.load()
        let migrated = try #require(loaded)
        #expect(migrated.reminderIDs == [item.id] && migrated.reminderSnoozes.isEmpty && migrated.checks == store.checks)
        let reopened = CheckStore(persistence: disk, now: { now })
        try reopened.snoozeDeviceReminder(id: item.id, until: now.addingTimeInterval(900))
        #expect(try disk.load()?.reminderSnoozes[item.id] == now.addingTimeInterval(900))
    }

    @Test func snoozeChoicesRespectElapsedTimeAndTomorrowAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let beforeFallBack = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9)))
        let tomorrow = try #require(ReminderSnoozeChoice.tomorrowMorning.due(after: beforeFallBack, calendar: calendar))
        #expect(calendar.dateComponents([.year, .month, .day, .hour], from: tomorrow) == DateComponents(year: 2026, month: 11, day: 1, hour: 9))
        #expect(tomorrow.timeIntervalSince(beforeFallBack) == 25 * 3600)
        #expect(ReminderSnoozeChoice.fifteenMinutes.due(after: now) == now.addingTimeInterval(900))
        #expect(ReminderSnoozeChoice.oneHour.due(after: now) == now.addingTimeInterval(3600))
        #expect(ReminderMessage.body(firstName: "  Robert\n", method: .phone) == "Call Robert for a Buddy Check")
        #expect(ReminderMessage.body(firstName: "Elena", method: .text) == "Text Elena for a Buddy Check")
        #expect(ReminderMessage.body(firstName: "James", method: .visit) == "Visit James for a Buddy Check")
        #expect(ReminderMessage.body(firstName: "Alex") == "Check in with Alex for a Buddy Check")
    }
}

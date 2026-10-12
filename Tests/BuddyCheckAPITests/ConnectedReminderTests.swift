import Foundation
import Testing
import BuddyCheckCore
@testable import BuddyCheckAPI

private func reminderRecord(id: Int = 14, due: Date = fixtureTime.addingTimeInterval(600),
                            status: FollowUpRecord.Status = .open, revision: Int = 0) -> FollowUpRecord {
    FollowUpRecord(id: id, personId: 42, contactId: nil, dueAt: due,
                   entryZone: "America/Chicago", status: status, revision: revision)
}

private actor ReminderTransport: HTTPTransport {
    var records = [reminderRecord()]
    var readError: ClientError?
    var personError: ClientError?
    var requests: [URLRequest] = []
    func change(_ records: [FollowUpRecord]) { self.records = records }
    func fail(_ error: ClientError?, personOnly: Bool = false) {
        if personOnly { personError = error } else { readError = error }
    }
    func captured() -> [URLRequest] { requests }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        switch request.url!.path {
        case "/oauth/token": return try response(#"{"access_token":"synthetic-token","token_type":"Bearer","expires_in":900,"scope":"buddy_check","created_at":1792000000}"#).get()
        case "/oauth/revoke": return try response("{}").get()
        case "/api/mobile/v1/session": return try response(sessionJSON).get()
        case "/api/mobile/v1/buddy-checks/follow-ups":
            if let readError { throw readError }
            let json = try String(decoding: WireJSON.encoder().encode(records), as: UTF8.self)
            return try response("{\"items\":\(json),\"next_cursor\":null}").get()
        case "/api/mobile/v1/buddy-checks/people/42":
            if let personError { throw personError }
            return try response(cardJSON).get()
        default: throw ClientError.invalidResponse
        }
    }
}

@MainActor private final class ReminderScheduler: ReminderScheduling {
    var permission: ReminderAuthorization = .notDetermined
    var permissionAfterPrompt: ReminderAuthorization = .allowed
    var prompts = 0
    var queued: [DeviceReminder] = []
    var shown: [DeviceReminder] = []
    var additions = 0
    var ignoreRemoval = false
    var suspendAdd = false
    var continuation: CheckedContinuation<Void, Never>?
    func authorization() async -> ReminderAuthorization { permission }
    func requestAuthorization() async throws { prompts += 1; permission = permissionAfterPrompt }
    func pending() async -> [DeviceReminder] { queued }
    func delivered() async -> [DeviceReminder] { shown }
    func schedule(_ reminder: DeviceReminder) async throws {
        additions += 1
        if suspendAdd { await withCheckedContinuation { continuation = $0 } }
        queued.removeAll { $0.id == reminder.id }; queued.append(reminder)
    }
    func finishAdd() { continuation?.resume(); continuation = nil }
    func remove(_ ids: [UUID]) async {
        guard !ignoreRemoval else { return }
        queued.removeAll { ids.contains($0.id) }; shown.removeAll { ids.contains($0.id) }
    }
}

@MainActor private final class ReminderHarness {
    let vault = TestVault()
    let disk = TestJournal()
    let transport = ReminderTransport()
    let scheduler = ReminderScheduler()
    var clock = fixtureTime
    var account: ConnectedAccount!
    func start() async throws {
        account = try makeAccount()
        let attempt = try account.beginAuthorization(now: clock)
        try await account.finishAuthorization(callback: URL(string: attempt.configuration.redirectURI.absoluteString + "?code=test&state=" + attempt.state)!, now: clock)
    }
    func makeAccount() throws -> ConnectedAccount {
        ConnectedAccount(client: BuddyCheckClient(configuration: try configuration(), transport: transport), vault: vault,
                         persistence: disk, reminderScheduler: { [scheduler] _ in scheduler }, reminderClock: { [unowned self] in self.clock })
    }
    var reminders: ConnectedReminders { account.reminders! }
}

@Suite @MainActor struct ConnectedReminderTests {
    @Test func explicitChoicePrecedesPermissionAndDenialRetainsIntent() async throws {
        let h = ReminderHarness(); try await h.start()
        await h.reminders.refresh()
        #expect(h.scheduler.prompts == 0 && h.disk.value?.phoneReminders == nil)
        h.scheduler.permissionAfterPrompt = .denied
        try await h.reminders.setEnabled(true, followUpID: 14)
        #expect(h.scheduler.prompts == 1 && h.scheduler.queued.isEmpty)
        #expect(h.reminders.status(14) == .denied && h.disk.value?.phoneReminders?[14] != nil)
        h.scheduler.permission = .allowed
        await h.reminders.refresh()
        #expect(h.scheduler.prompts == 1 && h.scheduler.queued.count == 1)
        #expect(h.reminders.status(14) == .scheduled)
    }
    @Test func persistenceFailureDoesNotPromptScheduleOrRemove() async throws {
        let h = ReminderHarness(); try await h.start(); h.disk.failWrites = true
        await #expect(throws: ClientError.journalUnavailable) { try await h.reminders.setEnabled(true, followUpID: 14) }
        #expect(h.scheduler.prompts == 0 && h.scheduler.additions == 0)
        h.disk.failWrites = false
        try await h.reminders.setEnabled(true, followUpID: 14)
        let original = h.scheduler.queued
        h.disk.failWrites = true
        await #expect(throws: ClientError.journalUnavailable) { try await h.reminders.setEnabled(false, followUpID: 14) }
        #expect(h.scheduler.queued == original && h.disk.value?.phoneReminders?.count == 1)
    }
    @Test func restorationReusesOpaqueIDAndDoesNotDuplicateOrPrompt() async throws {
        let h = ReminderHarness(); try await h.start()
        try await h.reminders.setEnabled(true, followUpID: 14)
        let intent = try #require(h.disk.value?.phoneReminders?[14])
        h.account.lock(); h.account = try h.makeAccount()
        try await h.account.restore(now: fixtureTime)
        await h.reminders.refresh(); await h.reminders.refresh()
        #expect(h.disk.value?.phoneReminders?[14] == intent)
        #expect(h.scheduler.queued.count == 1 && h.scheduler.queued.first?.hasSameSchedule(as: intent.deviceReminder) == true)
        #expect(h.scheduler.queued.first?.body == "Check in with Alex for a Buddy Check" && h.scheduler.additions == 1 && h.scheduler.prompts == 1)
        #expect(try ConnectedAccount.retainedReminderNamespace(vault: h.vault) == h.reminders.namespace)
    }
    @Test func serverRescheduleReplacesPendingAndOldDeliveredCopies() async throws {
        let h = ReminderHarness(); try await h.start()
        try await h.reminders.setEnabled(true, followUpID: 14)
        let initial = try #require(h.scheduler.queued.first)
        h.scheduler.shown = [initial]
        let changed = reminderRecord(due: fixtureTime.addingTimeInterval(800), revision: 1)
        await h.transport.change([changed]); await h.reminders.refresh()
        #expect(h.scheduler.queued == [DeviceReminder(id: initial.id, due: changed.dueAt, body: "Check in with Alex for a Buddy Check")])
        #expect(h.scheduler.shown.isEmpty && h.disk.value?.phoneReminders?[14]?.revision == 1)
        // Removing an old delivered copy also removes this ID's current pending
        // request. Reconciliation must replace that request in the same pass.
        h.scheduler.shown = [initial]
        await h.reminders.refresh()
        #expect(h.scheduler.queued == [DeviceReminder(id: initial.id, due: changed.dueAt, body: "Check in with Alex for a Buddy Check")] && h.scheduler.shown.isEmpty)
    }
    @Test(arguments: [FollowUpRecord.Status.completed, .cancelled])
    func closedOnServerRemovesIntentAndBothNotificationQueues(_ status: FollowUpRecord.Status) async throws {
        let h = ReminderHarness(); try await h.start()
        try await h.reminders.setEnabled(true, followUpID: 14)
        h.scheduler.shown = h.scheduler.queued
        await h.transport.change([reminderRecord(status: status, revision: 1)])
        await h.reminders.refresh()
        #expect(h.scheduler.queued.isEmpty && h.scheduler.shown.isEmpty && h.disk.value?.phoneReminders?.isEmpty == true)
        #expect(h.reminders.status(14) == .off)
        #expect(await h.transport.captured().filter { $0.httpMethod != "GET" }.allSatisfy { $0.url?.path == "/oauth/token" })
    }
    @Test func uncertainReadKeepsExistingAlertAndDoesNotScheduleFromDisk() async throws {
        let h = ReminderHarness(); try await h.start()
        try await h.reminders.setEnabled(true, followUpID: 14)
        let original = h.scheduler.queued
        await h.transport.fail(.connectionUnavailable); await h.reminders.refresh()
        #expect(h.scheduler.queued == original && h.reminders.status(14) == .unavailable)
        h.scheduler.queued = []; await h.reminders.refresh()
        #expect(h.scheduler.queued.isEmpty && h.scheduler.additions == 1 && h.disk.value?.phoneReminders?.count == 1)
    }
    @Test(arguments: [false, true])
    func missingFollowUpOrDeniedPersonRemovesOnlyOwnedIntent(_ personOnly: Bool) async throws {
        let h = ReminderHarness(); try await h.start()
        try await h.reminders.setEnabled(true, followUpID: 14)
        await h.transport.fail(.server(status: personOnly ? 403 : 404, code: "not_found"), personOnly: personOnly)
        await h.reminders.refresh()
        #expect(h.scheduler.queued.isEmpty && h.disk.value?.phoneReminders?.isEmpty == true)
    }
    @Test func expiryRetainsExistingAlertAndEncryptedIntentUntilSameAccountReturns() async throws {
        let h = ReminderHarness(); try await h.start()
        try await h.reminders.setEnabled(true, followUpID: 14)
        let before = h.scheduler.queued
        h.clock = fixtureTime.addingTimeInterval(901); await h.reminders.refresh()
        #expect(h.account.needsSignIn && h.account.journal == nil && h.scheduler.queued == before)
        #expect(h.disk.value?.phoneReminders?.count == 1 && h.scheduler.additions == 1)
        h.clock = fixtureTime; try await h.start(); await h.reminders.refresh()
        #expect(h.scheduler.queued == before && h.scheduler.additions == 1)
    }
    @Test func tapRequiresSameAccountAndFetchesCurrentFactsWithoutWriting() async throws {
        let h = ReminderHarness(); try await h.start()
        try await h.reminders.setEnabled(true, followUpID: 14)
        let alert = try #require(h.scheduler.queued.first)
        let before = await h.transport.captured().count
        await #expect(throws: ClientError.accountMismatch) {
            try await h.reminders.resolve(namespace: "connected.some-other-account", reminder: alert)
        }
        #expect(await h.transport.captured().count == before)
        await h.transport.change([reminderRecord(status: .completed, revision: 1)])
        let destination = try await h.reminders.resolve(namespace: h.reminders.namespace, reminder: alert)
        #expect(destination.changed && destination.record.status == .completed)
        let reads = await h.transport.captured().dropFirst(before)
        #expect(reads.count == 2 && reads.allSatisfy { $0.httpMethod == "GET" })
        await h.transport.fail(.connectionUnavailable)
        await #expect(throws: ClientError.connectionUnavailable) { try await h.reminders.resolve(namespace: h.reminders.namespace, reminder: alert) }
    }
    @Test func signOutAndRevocationRemovePendingDeliveredAndProtectedIntent() async throws {
        for revoke in [false, true] {
            let h = ReminderHarness(); try await h.start()
            try await h.reminders.setEnabled(true, followUpID: 14); h.scheduler.shown = h.scheduler.queued
            if revoke {
                await h.transport.fail(.server(status: 401, code: "revoked_session")); await h.reminders.refresh()
            } else { #expect(try await h.account.signOut()) }
            #expect(h.account.session == nil && h.account.reminders == nil && h.disk.value == nil && h.vault.values.isEmpty)
            #expect(h.scheduler.queued.isEmpty && h.scheduler.shown.isEmpty && !h.account.reminderRemovalUnconfirmed)
        }
    }
    @Test func signOutWaitsForSuspendedOSAddThenRemovesIt() async throws {
        let h = ReminderHarness(); try await h.start(); h.scheduler.suspendAdd = true
        let reminders = h.reminders
        let enable = Task { try await reminders.setEnabled(true, followUpID: 14) }
        for _ in 0..<1000 where h.scheduler.continuation == nil { await Task.yield() }
        try #require(h.scheduler.continuation != nil)
        defer { h.scheduler.finishAdd() }
        var signedOut = false
        let signOut = Task { let result = try await h.account.signOut(); signedOut = true; return result }
        for _ in 0..<1000 where h.account.session != nil { await Task.yield() }
        #expect(h.account.session == nil && !signedOut)
        h.scheduler.finishAdd()
        #expect(try await signOut.value)
        _ = try await enable.value
        #expect(h.scheduler.queued.isEmpty && h.disk.value == nil)
        await reminders.refresh()
        #expect(h.scheduler.additions == 1 && h.scheduler.queued.isEmpty)
    }
    @Test func failedOSRemovalIsReportedEvenWhenLocalSignOutSucceeds() async throws {
        let h = ReminderHarness(); try await h.start()
        try await h.reminders.setEnabled(true, followUpID: 14)
        h.scheduler.ignoreRemoval = true
        #expect(try await h.account.signOut())
        #expect(h.account.reminderRemovalUnconfirmed && !h.scheduler.queued.isEmpty)
        #expect(h.disk.value == nil && h.vault.values.isEmpty)
    }
    @Test func turnOffDuringSuspendedAddWinsAfterItFinishes() async throws {
        let h = ReminderHarness(); try await h.start(); h.scheduler.suspendAdd = true
        let enable = Task { try await h.reminders.setEnabled(true, followUpID: 14) }
        for _ in 0..<1000 where h.scheduler.continuation == nil { await Task.yield() }
        try #require(h.scheduler.continuation != nil)
        defer { h.scheduler.finishAdd() }
        try await h.reminders.setEnabled(false, followUpID: 14)
        h.scheduler.finishAdd(); try await enable.value
        #expect(h.scheduler.queued.isEmpty && h.disk.value?.phoneReminders?.isEmpty == true)
        #expect(h.reminders.status(14) == .off)
    }
    @Test func olderRevisionCannotReplaceLastVerifiedSchedule() async throws {
        let h = ReminderHarness(); try await h.start()
        await h.transport.change([reminderRecord(revision: 2)])
        try await h.reminders.setEnabled(true, followUpID: 14)
        let before = h.disk.value?.phoneReminders?[14]
        await h.transport.change([reminderRecord(due: fixtureTime.addingTimeInterval(800), revision: 1)])
        await h.reminders.refresh()
        #expect(h.reminders.status(14) == .unavailable && h.disk.value?.phoneReminders?[14] == before)
        let previous = try #require(before).deviceReminder
        #expect(h.scheduler.queued.count == 1 && h.scheduler.queued.first?.hasSameSchedule(as: previous) == true && h.scheduler.additions == 1)
    }
    @Test func viewTaskCancellationDoesNotAbandonPersistedReminderChoice() async throws {
        let h = ReminderHarness(); try await h.start(); h.scheduler.permission = .allowed
        try h.account.journal?.rememberReminder(ConnectedReminderIntent(record: reminderRecord()))
        let refresh = Task { await h.reminders.refresh() }
        refresh.cancel(); await refresh.value
        #expect(h.scheduler.queued.count == 1 && h.reminders.status(14) == .scheduled)
    }
    @Test func queueSelectsEarliestFiftyAndKeepsOverflowExplicit() async throws {
        let h = ReminderHarness(); try await h.start(); h.scheduler.permission = .allowed
        let records = (1...51).map { reminderRecord(id: $0, due: fixtureTime.addingTimeInterval(Double($0 * 10))) }
        await h.transport.change(records)
        for record in records.reversed() { try h.account.journal?.rememberReminder(ConnectedReminderIntent(record: record)) }
        await h.reminders.refresh()
        #expect(h.scheduler.queued.count == 50 && h.disk.value?.phoneReminders?.count == 51)
        #expect(h.reminders.status(1) == .scheduled && h.reminders.status(51) == .waiting)
        try await h.reminders.setEnabled(false, followUpID: 1)
        #expect(h.reminders.status(51) == .scheduled && h.scheduler.queued.count == 50)
    }
    @Test func intentIsMinimalEncryptedAndOlderJournalsDecodeWithoutIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let vault = TestVault(); let disk = EncryptedJournal(directory: folder, vault: vault)
        let journal = try SubmissionJournal(scope: scope(), persistence: disk)
        let old = try JSONEncoder().encode(journal.snapshot)
        #expect(try JSONDecoder().decode(JournalSnapshot.self, from: old).phoneReminders == nil)
        let intent = try ConnectedReminderIntent(record: reminderRecord())
        let encoded = try JSONEncoder().encode(intent)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == ["id", "followUpID", "due", "revision"])
        try journal.rememberReminder(intent)
        #expect(try disk.load(scope: scope())?.phoneReminders?[14] == intent)
        let bytes = try Data(contentsOf: disk.fileURL(scope()))
        #expect(bytes.range(of: Data(intent.id.uuidString.utf8)) == nil)
        #expect(try scope().reminderNamespace != scope(user: 8).reminderNamespace)
    }

    @Test func snoozeAfterDueUsesFreshAuthorityAndDoesNotMutateThePost() async throws {
        let h = ReminderHarness(); try await h.start()
        try await h.reminders.setEnabled(true, followUpID: 14)
        let original = try #require(h.scheduler.queued.first)
        h.clock = fixtureTime.addingTimeInterval(650)
        h.scheduler.queued = []; h.scheduler.shown = [original]
        let count = await h.transport.captured().count
        let until = h.clock.addingTimeInterval(900)
        try await h.reminders.snooze(followUpID: 14, until: until)
        let scheduled = try #require(h.scheduler.queued.first)
        #expect(scheduled.id == original.id && scheduled.due == until && h.scheduler.queued.count == 1)
        #expect(scheduled.body == "Check in with Alex for a Buddy Check" && h.scheduler.shown.isEmpty)
        #expect(h.disk.value?.phoneReminders?[14]?.due == original.due && h.reminders.snoozedUntil(14) == until)
        let requests = await h.transport.captured().dropFirst(count)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(requests.contains { $0.url?.path.hasSuffix("/people/42") == true })
        let destination = try await h.reminders.resolve(namespace: h.reminders.namespace, reminder: scheduled)
        #expect(!destination.changed && destination.record.status == .open && destination.record.dueAt == original.due)
        #expect(try await h.reminders.resolve(namespace: h.reminders.namespace, reminder: original).changed)
        h.account.lock(); h.account = try h.makeAccount(); try await h.account.restore(now: h.clock)
        await h.reminders.refresh()
        #expect(h.scheduler.queued == [scheduled] && h.scheduler.additions == 2)
        try await h.reminders.setEnabled(false, followUpID: 14)
        #expect(h.scheduler.queued.isEmpty && h.scheduler.shown.isEmpty && h.disk.value?.phoneReminders?.isEmpty == true)
        #expect(h.disk.value?.draft == nil && h.disk.value?.pending == nil)
    }

    @Test func snoozeFailureCannotScheduleAndServerDateChangeClearsOverride() async throws {
        let h = ReminderHarness(); try await h.start(); h.scheduler.permission = .allowed
        await h.transport.fail(.server(status: 403, code: "not_found"), personOnly: true)
        await #expect(throws: ClientError.self) { try await h.reminders.snooze(followUpID: 14, until: fixtureTime.addingTimeInterval(900)) }
        #expect(h.scheduler.additions == 0 && h.disk.value?.phoneReminders == nil)
        await h.transport.fail(nil, personOnly: true); h.disk.failWrites = true
        await #expect(throws: ClientError.journalUnavailable) { try await h.reminders.snooze(followUpID: 14, until: fixtureTime.addingTimeInterval(900)) }
        #expect(h.scheduler.additions == 0)
        h.disk.failWrites = false
        try await h.reminders.snooze(followUpID: 14, until: fixtureTime.addingTimeInterval(900))
        let originalID = h.scheduler.queued.first?.id
        await h.transport.change([reminderRecord(due: fixtureTime.addingTimeInterval(1800), revision: 1)])
        await h.reminders.refresh()
        #expect(h.reminders.snoozedUntil(14) == nil && h.scheduler.queued.first?.due == fixtureTime.addingTimeInterval(1800))
        #expect(h.scheduler.queued.count == 1 && h.scheduler.queued.first?.id == originalID)
    }

    @Test func snoozedIntentRoundTripsEncryptedWithoutMemberFields() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = EncryptedJournal(directory: folder, vault: TestVault())
        let journal = try SubmissionJournal(scope: scope(), persistence: disk)
        let intent = try ConnectedReminderIntent(record: reminderRecord(), snoozedUntil: fixtureTime.addingTimeInterval(1800))
        try journal.rememberReminder(intent)
        #expect(try disk.load(scope: scope())?.phoneReminders?[14] == intent)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any])
        #expect(Set(object.keys) == ["id", "followUpID", "due", "revision", "snoozedUntil"])
        var old = object; old.removeValue(forKey: "snoozedUntil")
        #expect(try JSONDecoder().decode(ConnectedReminderIntent.self, from: JSONSerialization.data(withJSONObject: old)).snoozedUntil == nil)
    }
}

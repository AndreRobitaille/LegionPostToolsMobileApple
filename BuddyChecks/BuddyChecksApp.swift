import SwiftUI
import BuddyCheckCore
import UserNotifications

@main struct BuddyChecksApp: App {
    @State private var store: CheckStore
    @State private var reminders: DeviceReminders
    private let reminderNamespace: String
    init() {
        let directory = Self.stateDirectory()
        let store = CheckStore(persistence: JSONSnapshotPersistence(fileURL: directory.appendingPathComponent("synthetic-checks.json")))
        #if DEBUG
        if UUID(uuidString: directory.lastPathComponent) != nil,
           let seconds = ProcessInfo.processInfo.environment["BUDDY_CHECKS_TEST_REMINDER_SECONDS"].flatMap(Double.init),
           (30...3600).contains(seconds), store.loadError == nil, store.checks.isEmpty {
            // Explicit, isolated synthetic fixture; OS notifications still use the real adapter.
            if let id = try? store.begin(personID: SyntheticDirectory.people[0].id, origin: .manual, timeZone: TimeZone.current.identifier) {
                try? store.updateDraft(id: id) { $0.outcome = .noAnswer; $0.followUpDue = Date().addingTimeInterval(seconds); $0.followUpTimeZone = TimeZone.current.identifier }
                _ = try? store.saveDraft(id: id, includeFollowUp: true)
            }
        }
        #endif
        _store = State(initialValue: store)
        reminderNamespace = directory.lastPathComponent
        _reminders = State(initialValue: DeviceReminders(store: store, scheduler: SystemReminderScheduler(namespace: directory.lastPathComponent)))
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }
    private static func stateDirectory() -> URL {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("BuddyChecks", isDirectory: true)
        #if DEBUG
        // Native UI tests use their own synthetic store, preserving the user's work.
        if let value = ProcessInfo.processInfo.environment["BUDDY_CHECKS_TEST_STORE"], let id = UUID(uuidString: value) {
            return directory.appendingPathComponent("UITests", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        }
        #endif
        return directory
    }
    var body: some Scene {
        WindowGroup { RootView(store: store, reminders: reminders, reminderNamespace: reminderNamespace).tint(Palette.action) }
    }
}

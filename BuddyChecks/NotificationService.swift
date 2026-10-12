import SwiftUI
import UserNotifications
import BuddyCheckCore
import BuddyCheckAPI

struct ReminderLink: Equatable {
    let namespace: String
    let reminder: DeviceReminder
}

@MainActor @Observable final class ReminderInbox {
    static let shared = ReminderInbox()
    var link: ReminderLink?
    var deliveryRevision = 0
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let request = response.notification.request
            let info = request.content.userInfo
            if let namespace = info["store"] as? String,
               let idString = info["follow_up"] as? String, let id = UUID(uuidString: idString),
               let due = info["due"] as? Double, due.isFinite,
               request.identifier == SystemReminderScheduler.identifier(namespace: namespace, id: id) {
                let link = ReminderLink(namespace: namespace, reminder: DeviceReminder(id: id, due: Date(timeIntervalSince1970: due)))
                Task { @MainActor in ReminderInbox.shared.link = link }
            }
        }
        completionHandler()
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in ReminderInbox.shared.deliveryRevision += 1 }
        completionHandler([.banner, .list, .sound])
    }
}

@MainActor final class SystemReminderScheduler: ReminderScheduling {
    private static var lastAdd: Task<Void, Error>?
    private static var addGeneration = UUID()
    private let center = UNUserNotificationCenter.current()
    let namespace: String
    init(namespace: String) { self.namespace = namespace }
    nonisolated static func identifier(namespace: String, id: UUID) -> String { "buddy-follow-up.\(namespace).\(id.uuidString)" }
    func authorization() async -> ReminderAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional, .ephemeral:
            return settings.alertSetting == .enabled ? .allowed : .denied
        case .denied: return .denied
        @unknown default: return .denied
        }
    }
    func requestAuthorization() async throws { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
    private func value(_ request: UNNotificationRequest) -> DeviceReminder? {
        let info = request.content.userInfo
        guard info["store"] as? String == namespace,
              let value = info["follow_up"] as? String, let id = UUID(uuidString: value),
              request.identifier == Self.identifier(namespace: namespace, id: id),
              let due = info["due"] as? Double, due.isFinite else { return nil }
        return DeviceReminder(id: id, due: Date(timeIntervalSince1970: due), body: request.content.body)
    }
    func pending() async -> [DeviceReminder] {
        await center.pendingNotificationRequests().compactMap { request in
            guard let value = value(request) else { return nil }
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  !trigger.repeats, let next = trigger.nextTriggerDate() else {
                return DeviceReminder(id: value.id, due: .distantPast, body: value.body)
            }
            // Use the OS trigger's actual date, not merely our requested payload.
            return DeviceReminder(id: value.id, due: next, body: value.body)
        }
    }
    func delivered() async -> [DeviceReminder] { await center.deliveredNotifications().compactMap { value($0.request) } }
    func schedule(_ reminder: DeviceReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Buddy Check follow-up"
        content.body = reminder.body
        content.sound = .default
        content.userInfo = ["store": namespace, "follow_up": reminder.id.uuidString, "due": reminder.due.timeIntervalSince1970]
        let request = UNNotificationRequest(identifier: Self.identifier(namespace: namespace, id: reminder.id), content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: reminder.utcComponents, repeats: false))
        // Serialize additions across local and connected stores; neither may
        // silently displace another store when the app's bounded queue is full.
        let previous = Self.lastAdd
        let generation = UUID(); Self.addGeneration = generation
        let task = Task { @MainActor [center] in
            if let previous { _ = try? await previous.value }
            let pending = await center.pendingNotificationRequests()
            guard pending.count < 50 || pending.contains(where: { $0.identifier == request.identifier })
            else { throw ClientError.invalidInput }
            try await center.add(request)
        }
        Self.lastAdd = task
        defer { if Self.addGeneration == generation { Self.lastAdd = nil } }
        try await task.value
    }
    func remove(_ ids: [UUID]) async {
        let identifiers = ids.map { Self.identifier(namespace: namespace, id: $0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    func removeAll() async -> Bool {
        await Self.removeRequests { $0.hasPrefix("buddy-follow-up.\(namespace).") }
    }
    /// Only one connected account is retained. Missing account storage is proof
    /// its old connected alerts are orphaned; unreadable storage is not.
    static func removeOrphanedConnectedAlerts() async {
        _ = await removeRequests { id in
            guard id.hasPrefix("buddy-follow-up.connected.") else { return false }
            do {
                // Read after the OS enumeration suspension, immediately before
                // removal. An account established during startup must survive.
                let retained = try ConnectedAccount.retainedReminderNamespace(vault: DeviceKeychain())
                return !(retained.map { id.hasPrefix("buddy-follow-up.\($0).") } ?? false)
            } catch { return false } // Preserve alerts while protected storage is unreadable.
        }
    }
    private static func removeRequests(matching owns: (String) -> Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter(owns))
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter(owns))
        let remaining = await center.pendingNotificationRequests()
        let shown = await center.deliveredNotifications()
        return !remaining.contains { owns($0.identifier) } && !shown.contains { owns($0.request.identifier) }
    }
}

struct ConnectedReminderControls: View {
    let record: FollowUpRecord
    let reminders: ConnectedReminders
    var body: some View {
        if record.status == .open {
            PhoneReminderControls(status: reminders.status(record.id), due: record.dueAt,
                snoozedUntil: reminders.snoozedUntil(record.id), busy: reminders.busy, connected: true,
                change: { try await reminders.setEnabled($0, followUpID: record.id) },
                snooze: { try await reminders.snooze(followUpID: record.id, until: $0) })
        }
    }
}

struct DeviceReminderControls: View {
    let item: FollowUp
    let reminders: DeviceReminders
    var body: some View {
        PhoneReminderControls(status: reminders.status(item.id), due: item.due,
            snoozedUntil: reminders.snoozedUntil(item.id), busy: reminders.busy, connected: false,
            change: { try await reminders.setEnabled($0, id: item.id) },
            snooze: { try await reminders.snooze(id: item.id, until: $0) })
    }
}

private struct PhoneReminderControls: View {
    let status: DeviceReminderStatus
    let due: Date
    let snoozedUntil: Date?
    let busy: Bool
    let connected: Bool
    let change: (Bool) async throws -> Void
    let snooze: (Date) async throws -> Void
    @Environment(\.openURL) private var openURL
    @State private var error: String?
    @State private var changing = false
    @State private var choosingSnooze = false
    private var effectiveDue: Date { snoozedUntil ?? due }
    var body: some View {
        WorkingSurface {
            SectionTitle("Phone reminder")
            Text(status == .denied && connected ? "Notifications are off. Your follow-up is saved with the Post." : status.label)
                .accessibilityIdentifier(connected ? "connected-reminder-status" : "device-reminder-status")
            if status == .scheduled, let snoozedUntil {
                Text("Snoozed until \(snoozedUntil.formatted(date: .abbreviated, time: .shortened)).")
                    .accessibilityIdentifier("reminder-snoozed-until")
            }
            if effectiveDue > Date(), [.off, .needsPermission, .unavailable].contains(status) {
                Button(status == .off ? "Remind me on this iPhone" : "Retry phone reminder") {
                    perform { try await change(true) }
                }.buttonStyle(ActionStyle(primary: false)).disabled(changing || busy)
            }
            if status != .checking && status != .denied && (status != .off || due <= Date()) {
                Button("Snooze reminder") { choosingSnooze = true }
                    .buttonStyle(ActionStyle(primary: false)).disabled(changing || busy)
            }
            if status == .denied {
                Button("Open notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }.buttonStyle(ActionStyle(primary: false))
            }
            if status != .off && status != .checking {
                Button("Dismiss reminder") { perform { try await change(false) } }
                    .buttonStyle(DismissReminderStyle()).disabled(changing || busy)
            }
            Text("Snoozing or dismissing the reminder leaves your follow-up open.").font(.footnote)
            if connected { Text("Changes made elsewhere update this alert when you reconnect to the Post.").font(.footnote) }
        }
        .sheet(isPresented: $choosingSnooze) {
            NavigationStack {
                Page {
                    Text("Remind me again in:")
                    ForEach(ReminderSnoozeChoice.allCases) { choice in
                        Button(choice.label) {
                            choosingSnooze = false
                            guard let date = choice.due(after: Date()) else { error = "Choose another reminder time."; return }
                            perform { try await snooze(date) }
                        }.buttonStyle(ActionStyle(primary: false))
                    }
                    if status != .off && status != .checking {
                        Button("Dismiss reminder") {
                            choosingSnooze = false
                            perform { try await change(false) }
                        }
                        .buttonStyle(DismissReminderStyle())
                        .accessibilityIdentifier("snooze-sheet-dismiss")
                        .padding(.top, 20)
                        .disabled(changing || busy)
                    }
                    Text("Your follow-up stays open with its original due time.").font(.footnote)
                }
                .navigationTitle("Snooze reminder")
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { choosingSnooze = false }
                        .foregroundStyle(Palette.surface).tint(Palette.surface)
                } }
            }.presentationDetents([.large])
        }
        .alert("Phone reminder", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "Please try again.") }
    }
    private func perform(_ action: @escaping () async throws -> Void) {
        changing = true; error = nil
        Task {
            defer { changing = false }
            do { try await action() }
            catch { self.error = connected ? safeMessage(error) : "The reminder choice couldn't be saved. Try again." }
        }
    }
}

private struct DismissReminderStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 16).padding(.vertical, 15)
            .foregroundStyle(Palette.red)
            .background(Palette.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.red, lineWidth: 1.25))
            .opacity(!enabled ? 0.5 : (configuration.isPressed ? 0.75 : 1))
    }
}

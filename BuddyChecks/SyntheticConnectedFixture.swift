#if DEBUG
import Foundation
import Contacts
import BuddyCheckAPI
import BuddyCheckCore
import BuddyCheckContacts

/// Explicit UI-test injection. Never opens a network connection or exposes a
/// dialable number. The guarded reminder fixture uses real protected storage on
/// named disposable simulators so SpringBoard can cold-start its saved account.
@MainActor enum SyntheticConnectedFixture {
    static var reminderTestingEnabled: Bool {
        #if targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        guard environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("Buddy Checks Connected Reminder") == true else { return false }
        if let seconds = environment["BUDDY_CHECKS_CONNECTED_REMINDER_SECONDS"].flatMap(Double.init), (45...3600).contains(seconds) {
            UserDefaults.standard.set(true, forKey: "test.connectedReminders")
            UserDefaults.standard.set(seconds, forKey: "test.connectedReminderSeconds")
        }
        return UserDefaults.standard.bool(forKey: "test.connectedReminders")
        #else
        return false
        #endif
    }
    static func contactsBackend(_ native: SystemContactsBackend) -> any ContactsBackend {
        #if targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        guard let rejection = environment["BUDDY_CHECKS_CONNECTED_REJECT_CONTACT_SAVE"],
              ["1", "native"].contains(rejection) else { return native }
        guard environment["SIMULATOR_DEVICE_NAME"] == "Legion Buddy Checks - iPhone 17 Pro",
              environment["BUDDY_CHECKS_CONNECTED_FIXTURE"] == "1",
              environment["BUDDY_CHECKS_CONNECTED_NATIVE_COMPANY_REVIEW"] != nil,
              let identifier = environment["BUDDY_CHECKS_CONNECTED_NATIVE_CONTACT"], !identifier.isEmpty,
              let store = environment["BUDDY_CHECKS_TEST_STORE"].flatMap(UUID.init(uuidString:)) else {
            preconditionFailure("Invalid synthetic Contacts rejection fixture")
        }
        let directory = URL.applicationSupportDirectory.appendingPathComponent("BuddyChecks/UITests/\(store.uuidString)", isDirectory: true)
        return RejectingContactsBackend(native: native, identifier: identifier, directory: directory,
                                        nativeRejection: rejection == "native")
        #else
        return native
        #endif
    }
    private final class RejectingContactsBackend: ContactsBackend {
        let native: SystemContactsBackend
        let identifier: String
        let directory: URL
        let nativeRejection: Bool
        init(native: SystemContactsBackend, identifier: String, directory: URL, nativeRejection: Bool) {
            self.native = native; self.identifier = identifier; self.directory = directory
            self.nativeRejection = nativeRejection
        }
        var access: ContactsAccess { native.access }
        func requestAccess() async throws { try await native.requestAccess() }
        func fetch(id: String, keys: [any CNKeyDescriptor]) throws -> CNContact {
            guard id == identifier else { throw ContactsError.unavailable }
            return try native.fetch(id: id, keys: keys)
        }
        func save(_ contact: CNMutableContact) throws {
            let before = ContactMapping.project(try fetch(id: identifier, keys: ContactMapping.keys))
            guard before.firstName == "Robert", before.lastName == "Miller",
                  before.company == "American Legion Post 165",
                  before.phones.contains(where: { $0.value == "+12025550101" }),
                  before.emails.contains(where: { $0.value == "robert.miller@example.org" }),
                  contact.identifier == identifier else { throw ContactsError.unavailable }
            var expected = before; expected.company = "Synthetic Contacts Update Test"
            guard ContactMapping.project(contact) == expected else { throw ContactsError.changedDuringReview }
            let rejection: NSError
            if nativeRejection {
                // CNSaveRequest documents that updating a never-saved object
                // fails with recordDoesNotExist. Do not submit Robert's update
                // or add/delete any contact to provoke this real service error.
                let missing = CNMutableContact()
                missing.givenName = "Synthetic Missing Record"
                do {
                    try native.save(missing)
                    preconditionFailure("Contacts accepted an update to an unsaved record")
                } catch {
                    let nativeError = error as NSError
                    guard nativeError.domain == CNErrorDomain,
                          nativeError.code == CNError.Code.recordDoesNotExist.rawValue else { throw error }
                    rejection = nativeError
                }
            } else { rejection = CocoaError(.fileWriteNoPermission) as NSError }
            let after = ContactMapping.project(try fetch(id: identifier, keys: ContactMapping.keys))
            guard before == after else { throw ContactsError.changedDuringReview }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("rejected-contact-saves.json")
            var events = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
            events.append(["injected_rejection": !nativeRejection, "native_save_called": nativeRejection,
                           "native_error_domain": rejection.domain, "native_error_code": rejection.code,
                           "native_card_unchanged": true,
                           "requested_company": expected.company, "native_company": after.company])
            try JSONSerialization.data(withJSONObject: events, options: [.sortedKeys, .prettyPrinted]).write(to: file, options: .atomic)
            throw rejection
        }
    }
    static func account() async throws -> ConnectedAccount {
        let nativeCompany = try nativeCompanyReview()
        let contactDirectory = try contactCreationDirectory()
        let workflowDirectory: URL?
        #if targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        if environment["BUDDY_CHECKS_CONNECTED_WORKFLOW_STORE"] == "1",
           let store = environment["BUDDY_CHECKS_TEST_STORE"].flatMap(UUID.init(uuidString:)) {
            workflowDirectory = URL.applicationSupportDirectory.appendingPathComponent("BuddyChecks/UITests/\(store.uuidString)/Workflow", isDirectory: true)
        } else { workflowDirectory = nil }
        #else
        workflowDirectory = nil
        #endif
        let interruption = ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONNECTED_CREATION_INTERRUPTION"]
        if let interruption {
            guard let contactDirectory, ["arm", "resume"].contains(interruption) else { throw ClientError.invalidResponse }
            let consumed = FileManager.default.fileExists(atPath: contactDirectory.appendingPathComponent("native-save-before-link.json").path)
            guard interruption == "resume" || !consumed else { throw ClientError.invalidResponse }
            if interruption == "arm" {
                guard try recoveryNativeContactIDs().isEmpty else { throw ClientError.invalidResponse }
            } else { guard consumed else { throw ClientError.invalidResponse } }
        }
        let configuration = try ConnectionConfiguration(issuer: URL(string: "https://synthetic.example.test")!, clientID: "synthetic-public-client",
                                                        redirectURI: URL(string: "org.wipost165.buddychecks:/oauth/callback")!)
        let persistentReminder = reminderTestingEnabled
        let directory = contactDirectory ?? URL.applicationSupportDirectory.appendingPathComponent("BuddyChecks/Connected", isDirectory: true)
        let reminderFile: URL?
        if persistentReminder {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            reminderFile = directory.appendingPathComponent("synthetic-reminder-fixture.json")
        } else { reminderFile = nil }
        let transport = try FixtureTransport(loseFirstResponse: ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONNECTED_LOST_RESPONSE"] == "1",
                                         permitsExport: ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONNECTED_EXPORT"] == "1",
                                         paused: ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONNECTED_PAUSED"] == "1",
                                         staleCorrection: ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONNECTED_STALE_CORRECTION"] == "1",
                                         changedFollowUp: ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONNECTED_CHANGED_FOLLOW_UP"] == "1",
                                         changedExport: ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONNECTED_CHANGED_EXPORT"] == "1",
                                         changedMember: ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONNECTED_CHANGED_MEMBER"] == "1",
                                         randomSuggestions: ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONNECTED_RANDOM_SUGGESTIONS"] == "1",
                                         reminderFile: reminderFile, reminderSeconds: UserDefaults.standard.double(forKey: "test.connectedReminderSeconds"),
                                         contactCompany: nativeCompany ?? "American Legion Post 165",
                                         contactFirstName: interruption == nil ? "Alex" : "Taylor", contactLastName: interruption == nil ? "Example" : "Recovery",
                                         contactEmail: interruption != nil ? "taylor.recovery@example.test" : contactDirectory != nil && ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONNECTED_CREATION_EMAIL_UPDATE"] == "1" ? "alex.updated@example.test" : "alex@example.test")
        let vault: any SecretVault
        let journal: any JournalPersistence
        if let contactDirectory {
            vault = DeviceKeychain(service: "org.wipost165.buddychecks.native-creation." + contactDirectory.deletingLastPathComponent().lastPathComponent)
            journal = FixtureContactsJournal(base: EncryptedJournal(directory: contactDirectory, vault: vault), directory: contactDirectory)
        } else if let workflowDirectory {
            // Unsigned simulator UI builds cannot use Keychain entitlements.
            // Persist only this isolated fixture's synthetic secrets; exercise
            // the production encrypted journal without changing DeviceKeychain.
            #if targetEnvironment(simulator)
            vault = FixtureWorkflowVault(directory: workflowDirectory)
            #else
            throw ClientError.invalidInput
            #endif
            journal = EncryptedJournal(directory: workflowDirectory, vault: vault)
        } else {
            vault = persistentReminder ? DeviceKeychain() : FixtureVault()
            journal = persistentReminder ? EncryptedJournal(directory: directory, vault: vault) : FixtureJournal()
        }
        let account = ConnectedAccount(client: BuddyCheckClient(configuration: configuration, transport: transport), vault: vault, persistence: journal,
                                       reminderScheduler: { namespace in
            if persistentReminder {
                return FixtureReminderScheduler(namespace: namespace, file: directory.appendingPathComponent("synthetic-reminder-os.json"))
            }
            return SystemReminderScheduler(namespace: contactDirectory.map { "test.contacts." + $0.deletingLastPathComponent().lastPathComponent } ?? namespace)
        })
        if persistentReminder || contactDirectory != nil || workflowDirectory != nil {
            try await account.restore()
            if account.session != nil { return account }
        }
        let attempt = try account.beginAuthorization()
        let callback = URL(string: configuration.redirectURI.absoluteString + "?code=synthetic-code&state=" + attempt.state)!
        try await account.finishAuthorization(callback: callback)
        if ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONNECTED_CHANGED_EXPORT"] == "1" {
            try account.journal?.rememberContact(personID: 42, link: .init(contactID: "synthetic-retained-contact-link", creationPending: true))
        }
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Legion Buddy Checks - iPhone 17 Pro",
           let identifier = ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONNECTED_NATIVE_CONTACT"], !identifier.isEmpty {
            // An explicit test may reuse the already-approved synthetic card.
            // No native contact is written and the normal app journal is untouched.
            try account.journal?.rememberContact(personID: 42, link: .init(contactID: identifier))
        }
        #endif
        return account
    }
    private static func contactCreationDirectory() throws -> URL? {
        #if targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        guard environment["BUDDY_CHECKS_CONNECTED_NATIVE_CREATION"] == "1" else { return nil }
        guard environment["SIMULATOR_DEVICE_NAME"] == "Legion Buddy Checks - iPhone 17 Pro",
              environment["BUDDY_CHECKS_CONNECTED_NATIVE_CONTACT"] == nil,
              let store = environment["BUDDY_CHECKS_TEST_STORE"].flatMap(UUID.init(uuidString:)) else { throw ClientError.invalidResponse }
        return URL.applicationSupportDirectory.appendingPathComponent("BuddyChecks/UITests/\(store.uuidString)/ConnectedContacts", isDirectory: true)
        #else
        return nil
        #endif
    }
    static func recoveryNativeContactIDs() throws -> [String] {
        try CNContactStore().unifiedContacts(matching: CNContact.predicateForContacts(matchingName: "Taylor Recovery"),
            keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor])
            .filter { $0.givenName == "Taylor" && $0.familyName == "Recovery" }.map(\.identifier)
    }
    /// Holds only the approved native-creation fixture after the OS save and
    /// before the production completion/link write. XCTest terminates the app here.
    static func holdSavedContactBeforeLink(_ contact: CNContact) throws -> Bool {
        #if targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        guard environment["BUDDY_CHECKS_CONNECTED_CREATION_INTERRUPTION"] == "arm" else { return false }
        guard environment["BUDDY_CHECKS_CONNECTED_FIXTURE"] == "1",
              let directory = try contactCreationDirectory() else { throw ClientError.invalidResponse }
        let file = directory.appendingPathComponent("native-save-before-link.json")
        guard !FileManager.default.fileExists(atPath: file.path) else { throw ClientError.invalidResponse }
        let native = try AppleContactsService(backend: SystemContactsBackend()).fetch(id: contact.identifier)
        guard native.firstName == "Taylor", native.lastName == "Recovery", native.company == "American Legion Post 165",
              native.phones.isEmpty, native.addresses.isEmpty, native.emails.count == 1,
              native.emails[0].value == "taylor.recovery@example.test" else { throw ClientError.invalidResponse }
        let data: [String: Any] = ["native_id": native.id, "email_id": native.emails[0].id,
            "native_save_read_back": true, "app_completion_delivered": false,
            "matching_native_ids": try recoveryNativeContactIDs()]
        try JSONSerialization.data(withJSONObject: data, options: [.sortedKeys, .prettyPrinted]).write(to: file, options: .atomic)
        return true
        #else
        return false
        #endif
    }
    /// Reads only the explicitly approved synthetic card. Writes diagnostic JSON,
    /// never Contacts; the normal review/save UI performs the selected field update.
    private static func nativeCompanyReview() throws -> String? {
        #if targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        guard let phase = environment["BUDDY_CHECKS_CONNECTED_NATIVE_COMPANY_REVIEW"] else { return nil }
        guard environment["SIMULATOR_DEVICE_NAME"] == "Legion Buddy Checks - iPhone 17 Pro",
              let identifier = environment["BUDDY_CHECKS_CONNECTED_NATIVE_CONTACT"], !identifier.isEmpty,
              let store = environment["BUDDY_CHECKS_TEST_STORE"].flatMap(UUID.init(uuidString:)),
              ["before", "updated", "restored"].contains(phase) else { throw ClientError.invalidResponse }
        let contact = try AppleContactsService(backend: SystemContactsBackend()).fetch(id: identifier)
        let original = "American Legion Post 165"
        let temporary = "Synthetic Contacts Update Test"
        guard contact.firstName == "Robert", contact.lastName == "Miller",
              contact.phones.contains(where: { $0.value == "+12025550101" }),
              contact.emails.contains(where: { $0.value == "robert.miller@example.org" }),
              contact.company == (phase == "updated" ? temporary : original) else { throw ClientError.invalidResponse }
        func strings(_ items: [ContactItem<String>]) -> [[String: Any]] {
            items.map { ["id": $0.id, "label": $0.label as Any? ?? NSNull(), "value": $0.value] }
        }
        let snapshot: [String: Any] = ["phase": phase, "id": contact.id, "first_name": contact.firstName,
            "last_name": contact.lastName, "company": contact.company, "phones": strings(contact.phones), "emails": strings(contact.emails),
            "addresses": contact.addresses.map { ["id": $0.id, "label": $0.label as Any? ?? NSNull(),
                "street": $0.value.street, "city": $0.value.city, "state": $0.value.state,
                "postal_code": $0.value.postalCode, "country": $0.value.country] }]
        let directory = URL.applicationSupportDirectory.appendingPathComponent("BuddyChecks/UITests/\(store.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys, .prettyPrinted])
            .write(to: directory.appendingPathComponent("native-contact-\(phase).json"), options: .atomic)
        return phase == "before" ? temporary : original
        #else
        return nil
        #endif
    }
    private final class FixtureVault: SecretVault {
        var values: [String: Data] = [:]
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { values[key] = data }
        func remove(_ key: String) throws { values[key] = nil }
    }
    private final class FixtureJournal: JournalPersistence {
        var value: JournalSnapshot?
        func load(scope: AccountScope) throws -> JournalSnapshot? { value }
        func save(_ snapshot: JournalSnapshot) throws { value = snapshot }
        func purge(scope: AccountScope) throws { value = nil }
    }
}

#if targetEnvironment(simulator)
@MainActor private final class FixtureWorkflowVault: SecretVault {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    private var file: URL { directory.appendingPathComponent("synthetic-vault.json") }
    private func values() throws -> [String: Data] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        return try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: file))
    }
    func read(_ key: String) throws -> Data? { try values()[key] }
    func write(_ data: Data, key: String) throws {
        var next = try values(); next[key] = data; try save(next)
    }
    func remove(_ key: String) throws {
        var next = try values(); next[key] = nil; try save(next)
    }
    private func save(_ next: [String: Data]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
    }
}
#endif

/// Observe only this isolated fixture's opaque links and its verified new card.
/// Real Keychain/encrypted persistence remains responsible for restoration.
@MainActor private final class FixtureContactsJournal: JournalPersistence {
    let base: EncryptedJournal
    let directory: URL
    init(base: EncryptedJournal, directory: URL) { self.base = base; self.directory = directory }
    private func record(_ event: String, _ snapshot: JournalSnapshot?) throws {
        var item: [String: Any] = ["event": event,
            "links": try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot?.contactLinks ?? [:]))]
        if let id = snapshot?.contactLinks?[42]?.contactID,
           let native = try? AppleContactsService(backend: SystemContactsBackend()).fetch(id: id),
           ((native.firstName == "Alex" && native.lastName == "Example" && native.emails.allSatisfy({ ["alex@example.test", "alex.updated@example.test"].contains($0.value) }))
            || (native.firstName == "Taylor" && native.lastName == "Recovery" && native.emails.allSatisfy({ $0.value == "taylor.recovery@example.test" }))),
           native.company == "American Legion Post 165" {
            item["native"] = ["id": native.id, "first_name": native.firstName, "last_name": native.lastName, "company": native.company,
                "emails": native.emails.map { ["id": $0.id, "label": $0.label as Any? ?? NSNull(), "value": $0.value] },
                "phone_count": native.phones.count, "address_count": native.addresses.count]
            if native.firstName == "Taylor" && native.lastName == "Recovery" {
                item["matching_native_ids"] = try SyntheticConnectedFixture.recoveryNativeContactIDs()
            }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("contacts-journal-events.json")
        var events = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        events.append(item)
        try JSONSerialization.data(withJSONObject: events, options: [.sortedKeys, .prettyPrinted]).write(to: file, options: .atomic)
    }
    func load(scope: AccountScope) throws -> JournalSnapshot? { let value = try base.load(scope: scope); try record("load", value); return value }
    func save(_ snapshot: JournalSnapshot) throws { try base.save(snapshot); try record("save", snapshot) }
    func purge(scope: AccountScope) throws { try base.purge(scope: scope); try record("purge", nil) }
}

/// Read-only diagnostic observations around the real OS adapter. Only the named,
/// explicitly enabled disposable fixture uses this; no contact fields or tokens.
@MainActor private final class FixtureReminderScheduler: ReminderScheduling {
    private let system: SystemReminderScheduler
    private let file: URL
    init(namespace: String, file: URL) { system = SystemReminderScheduler(namespace: namespace); self.file = file }
    private func record(_ event: String, _ value: Any) {
        var events = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        events.append(["event": event, "value": value, "time": Date().timeIntervalSince1970])
        if let data = try? JSONSerialization.data(withJSONObject: events, options: [.sortedKeys]) { try? data.write(to: file, options: .atomic) }
    }
    private func values(_ items: [DeviceReminder]) -> [[String: Any]] { items.map { ["id": $0.id.uuidString, "due": $0.due.timeIntervalSince1970] } }
    func authorization() async -> ReminderAuthorization {
        let value = await system.authorization(); record("authorization", String(describing: value)); return value
    }
    func requestAuthorization() async throws { try await system.requestAuthorization(); record("permissionReturned", true) }
    func pending() async -> [DeviceReminder] { let value = await system.pending(); record("pending", values(value)); return value }
    func delivered() async -> [DeviceReminder] { let value = await system.delivered(); record("delivered", values(value)); return value }
    func schedule(_ reminder: DeviceReminder) async throws {
        do { try await system.schedule(reminder); record("added", values([reminder])) }
        catch { record("addFailed", ["domain": (error as NSError).domain, "code": (error as NSError).code]); throw error }
    }
    func remove(_ ids: [UUID]) async { await system.remove(ids); record("remove", ids.map(\.uuidString)) }
    func removeAll() async -> Bool { let result = await system.removeAll(); record("removedAllConfirmed", result); return result }
}

actor FixtureTransport: HTTPTransport {
    var receipts: [String: Data] = [:]
    var contacts: [[String: Any]] = []
    var revisions: [[String: Any]] = []
    var followUps: [[String: Any]] = []
    var snoozes: [[String: Any]] = []
    var loseFirstResponse: Bool
    let permitsExport: Bool
    let paused: Bool
    var staleCorrection: Bool
    let changedFollowUp: Bool
    let changedExport: Bool
    let changedMember: Bool
    let randomSuggestions: Bool
    let contactCompany: String
    let contactEmail: String
    let contactFirstName: String
    let contactLastName: String
    var memberReads = 0
    var exportReads = 0
    let reminderFile: URL?
    var followUpReads = 0
    init(loseFirstResponse: Bool, permitsExport: Bool, paused: Bool, staleCorrection: Bool, changedFollowUp: Bool, changedExport: Bool = false, changedMember: Bool = false, randomSuggestions: Bool = false,
         reminderFile: URL? = nil, reminderSeconds: Double = 300, contactCompany: String = "American Legion Post 165", contactFirstName: String = "Alex", contactLastName: String = "Example", contactEmail: String = "alex@example.test") throws {
        self.loseFirstResponse = loseFirstResponse; self.permitsExport = permitsExport; self.paused = paused
        self.staleCorrection = staleCorrection; self.changedFollowUp = changedFollowUp
        self.changedExport = changedExport
        self.changedMember = changedMember
        self.randomSuggestions = randomSuggestions
        self.contactCompany = contactCompany
        self.contactFirstName = contactFirstName; self.contactLastName = contactLastName
        self.contactEmail = contactEmail
        self.reminderFile = reminderFile
        if let reminderFile {
            if FileManager.default.fileExists(atPath: reminderFile.path) {
                followUps = try JSONSerialization.jsonObject(with: Data(contentsOf: reminderFile)) as! [[String: Any]]
            } else {
                let formatter = ISO8601DateFormatter()
                followUps = [["id": 14, "person_id": 42, "contact_id": NSNull(), "due_at": formatter.string(from: Date().addingTimeInterval(reminderSeconds)),
                              "entry_zone": "America/Chicago", "status": "open", "revision": 0]]
                try JSONSerialization.data(withJSONObject: followUps).write(to: reminderFile, options: .atomic)
            }
        }
        if changedFollowUp {
            followUps = [["id": 14, "person_id": 42, "contact_id": NSNull(), "due_at": "2026-10-14T20:30:00.000Z",
                          "entry_zone": "America/Chicago", "status": "open", "revision": 1]]
        }
        if staleCorrection {
            let contact: [String: Any] = ["id": 81, "source_id": 81, "person_id": 42, "revision": 1,
                "channel": "phone", "outcome": "no_answer", "precision": "instant", "occurred_on": "2026-10-11",
                "occurred_at": "2026-10-11T20:30:00.000Z", "entry_zone": "America/Chicago", "membership_year": 2026,
                "notes": "Original synthetic attempt.", "legacy_follow_up_on": NSNull(), "recorded_at": "2026-10-11T20:31:00.000Z"]
            contacts = [contact]; revisions = [contact]
        }
    }
    private func instant(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    private func response(_ object: [String: Any], status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(data: try JSONSerialization.data(withJSONObject: object), status: status)
    }
    private var coverage: [String: Any] {
        ["contact_history": "partial", "missing_history": "unknown", "attendance": "explicit_registers_only", "checked_at": instant()]
    }
    private var identity: [String: Any] { ["id": 42, "first_name": contactFirstName, "last_name": contactLastName] }
    private var eligibility: [String: Any] {
        ["eligible": true, "reason": NSNull(), "checked_at": instant(), "expires_at": instant(Date().addingTimeInterval(60))]
    }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let path = request.url?.path ?? ""
        if path == "/oauth/token" {
            return try response(["access_token": "synthetic-only-token", "token_type": "Bearer", "expires_in": 900, "scope": "buddy_check", "created_at": Int(Date().timeIntervalSince1970)])
        }
        if path == "/oauth/revoke" { return try response([:]) }
        if path.hasSuffix("/session") {
            return try response(["installation": ["id": 1, "issuer": "https://synthetic.example.test", "name": "Synthetic Post", "timezone": "America/Chicago"],
                                 "user": ["id": 7, "name": "Jamie Example"], "session_id": 23, "expires_at": instant(Date().addingTimeInterval(900)),
                                 "capabilities": ["buddy_checks": true, "contacts_export": permitsExport, "refresh": false]])
        }
        if path.hasSuffix("/people") {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
            let matches = (contactFirstName + " " + contactLastName).localizedCaseInsensitiveContains(query)
            return try response(["items": query.isEmpty || matches ? [identity] : [], "next_cursor": NSNull()])
        }
        if path.hasSuffix("/people/42") {
            memberReads += 1
            var currentEligibility = eligibility
            let currentlyPaused = paused || (changedMember && memberReads == 2)
            if currentlyPaused { currentEligibility["eligible"] = false; currentEligibility["reason"] = "contact_paused" }
            var currentIdentity = identity
            if changedMember {
                if memberReads == 3 { return try response(["error": ["code": "not_found"]], status: 404) }
                if memberReads == 4 { throw ClientError.connectionUnavailable }
                if memberReads == 5 { currentIdentity["id"] = 43 }
                if memberReads >= 6 { currentIdentity["first_name"] = "Avery" }
            }
            return try response(currentIdentity.merging(["phone": NSNull(), "email": NSNull(), "assignment_ids": [], "export_available": permitsExport, "eligibility": currentEligibility, "coverage": coverage]) { _, new in new })
        }
        if path == "/api/mobile/v1/people/42/contact-export" {
            guard permitsExport else { return try response(["error": ["code": "export_disabled"]], status: 403) }
            exportReads += 1
            if changedExport {
                if exportReads == 2 { return try response(["error": ["code": "export_disabled"]], status: 403) }
                if exportReads == 6 { throw ClientError.connectionUnavailable }
                let revision = exportReads < 3 ? "first" : "current"
                return try response(["person_id": 42, "source": "legion_post_tools/person/42", "version": "synthetic-export-\(revision)",
                                     "fields": ["first_name": "Alex", "last_name": "Example", "company": "American Legion Post 165", "phone": NSNull(), "email": "\(revision)@example.test", "address": [:]],
                                     "permitted_fields": exportReads == 4 ? ["company"] : ["first_name", "last_name", "company", "email"],
                                     "address_coverage": "not_permitted", "address_review_id": NSNull(), "checked_at": instant()])
            }
            return try response(["person_id": 42, "source": "legion_post_tools/person/42", "version": "synthetic-export-version",
                                 "fields": ["first_name": contactFirstName, "last_name": contactLastName, "company": contactCompany, "phone": NSNull(), "email": contactEmail, "address": [:]],
                                 "permitted_fields": ["first_name", "last_name", "company", "phone", "email"], "address_coverage": "not_permitted", "address_review_id": NSNull(), "checked_at": instant()])
        }
        if path.hasSuffix("/suggestion") {
            if randomSuggestions {
                return try response(["state": "insufficient_history", "coverage": coverage, "random_candidates": [
                    identity, ["id": 43, "first_name": "Taylor", "last_name": "Example"],
                    ["id": 44, "first_name": "Morgan", "last_name": "Example"]]])
            }
            if snoozes.contains(where: { $0["cancelled_at"] is NSNull }) { return try response(["state": "exhausted", "coverage": coverage]) }
            if URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "exclude_ids[]" && $0.value == "42" }) == true {
                return try response(["state": "insufficient_history", "coverage": coverage])
            }
            return try response(["state": "candidate", "person": identity, "reason": "recorded_contact_is_older", "reason_on": "2026-07-03",
                                 "attendance": ["coverage": "unknown", "meetings": []], "eligibility": eligibility, "coverage": coverage])
        }
        if path.contains("/receipts/") {
            if let saved = receipts[request.url!.lastPathComponent.lowercased()] { return HTTPResponse(data: saved, status: 200) }
            return try response(["error": ["code": "not_found"]], status: 404)
        }
        if path.hasSuffix("/buddy-checks") && request.httpMethod == "POST" {
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let id = body["operation_id"] as! String
            if let saved = receipts[id.lowercased()] { return HTTPResponse(data: saved, status: 201) }
            var contact = body["facts"] as! [String: Any]
            contact.merge(["id": 81, "source_id": 81, "person_id": 42, "revision": 1, "precision": "instant", "occurred_on": "2026-10-11",
                           "membership_year": 2026, "legacy_follow_up_on": NSNull(), "recorded_at": instant()]) { _, new in new }
            contacts.append(contact)
            revisions.append(contact)
            var followUp: [String: Any]?
            if var requested = body["follow_up"] as? [String: Any] {
                requested.merge(["id": 14, "person_id": 42, "contact_id": 81, "status": "open", "revision": 0]) { _, new in new }
                followUps.append(requested); followUp = requested
            }
            let result = try response(["operation_id": id, "accepted_at": instant(), "state": "accepted", "contact": contact, "follow_up": followUp as Any? ?? NSNull()], status: 201)
            receipts[id.lowercased()] = result.data
            if loseFirstResponse { loseFirstResponse = false; throw ClientError.connectionUnavailable }
            return result
        }
        if path.hasSuffix("/mine") { return try response(["items": contacts, "next_cursor": NSNull()]) }
        if path.hasSuffix("/81/revisions") { return try response(["items": revisions, "next_cursor": NSNull()]) }
        if path.hasSuffix("/81/corrections"), let body = request.httpBody,
           let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any], var current = contacts.first {
            if staleCorrection {
                staleCorrection = false
                current["revision"] = 2; current["source_id"] = 82; current["outcome"] = "wrong_number"
                current["notes"] = "Updated in another session."
                contacts = [current]; revisions.append(current)
            }
            guard payload["expected_revision"] as? Int == current["revision"] as? Int else { return try response(["error": ["code": "stale_revision"]], status: 409) }
            current.merge(payload["facts"] as! [String: Any]) { _, new in new }
            current["revision"] = (current["revision"] as! Int) + 1
            current["source_id"] = (current["source_id"] as! Int) + 1
            current["recorded_at"] = instant()
            contacts = [current]; revisions.append(current)
            return try accepted(payload: payload, values: ["contact": current])
        }
        if path.hasSuffix("/follow-ups/14/changes"), let body = request.httpBody,
           let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any], var current = followUps.first {
            guard current["status"] as? String == "open" else { return try response(["error": ["code": "follow_up_closed"]], status: 409) }
            guard payload["expected_revision"] as? Int == current["revision"] as? Int else { return try response(["error": ["code": "stale_revision"]], status: 409) }
            switch payload["action"] as? String {
            case "complete": current["status"] = "completed"
            case "cancel": current["status"] = "cancelled"
            default: current["due_at"] = payload["due_at"]; current["entry_zone"] = payload["entry_zone"]
            }
            current["revision"] = (current["revision"] as! Int) + 1
            followUps = [current]
            if let reminderFile { try JSONSerialization.data(withJSONObject: followUps).write(to: reminderFile, options: .atomic) }
            return try accepted(payload: payload, values: ["follow_up": current])
        }
        if path.hasSuffix("/snoozes") && request.httpMethod == "POST", let body = request.httpBody,
           let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            let snooze: [String: Any] = ["id": 19, "person_id": 42, "until_at": payload["until_at"]!, "cancelled_at": NSNull(), "revision": 0]
            snoozes = [snooze]
            return try accepted(payload: payload, values: ["snooze": snooze])
        }
        if path.hasSuffix("/snoozes/19") && request.httpMethod == "DELETE", let body = request.httpBody,
           let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any], var snooze = snoozes.first {
            snooze["revision"] = 1; snooze["cancelled_at"] = instant(); snoozes = [snooze]
            return try accepted(payload: payload, values: ["snooze": snooze])
        }
        if path.hasSuffix("/snoozes") { return try response(["items": snoozes, "next_cursor": NSNull()]) }
        if path.hasSuffix("/follow-ups") {
            followUpReads += 1
            if changedFollowUp && followUpReads >= 2 {
                // The list was true when read; another session closed it before selection.
                followUps[0]["status"] = "completed"; followUps[0]["revision"] = 2
                if followUpReads == 3 { throw ClientError.connectionUnavailable }
            }
            return try response(["items": followUps, "next_cursor": NSNull()])
        }
        return try response(["error": ["code": "not_found"]], status: 404)
    }
    private func accepted(payload: [String: Any], values: [String: Any]) throws -> HTTPResponse {
        let id = payload["operation_id"] as! String
        let result = try response(values.merging(["operation_id": id, "accepted_at": instant(), "state": "accepted"]) { _, new in new }, status: 201)
        receipts[id.lowercased()] = result.data
        return result
    }
}
#endif

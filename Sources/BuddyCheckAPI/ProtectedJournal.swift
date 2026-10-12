import CryptoKit
import Foundation
import Security

public struct AccountScope: Codable, Equatable, Sendable {
    public let issuer: URL
    public let installationID: Int
    public let userID: Int
    public init(configuration: ConnectionConfiguration, session: MobileSession) throws {
        guard session.installation.issuer == configuration.issuer.absoluteString else { throw ClientError.accountMismatch }
        issuer = configuration.issuer; installationID = session.installation.id; userID = session.user.id
    }
    init(configuration: ConnectionConfiguration, credential: AccessCredential) throws {
        guard credential.issuer == configuration.issuer,
              let installation = credential.installationId, installation > 0,
              let user = credential.userId, user > 0 else { throw ClientError.accountMismatch }
        issuer = configuration.issuer; installationID = installation; userID = user
    }
    var storageKey: String {
        let value = "\(issuer.absoluteString)\n\(installationID)\n\(userID)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public var reminderNamespace: String { "connected." + storageKey }
}

public struct ConnectedDraft: Codable, Equatable, Sendable {
    public let id: UUID
    public let personID: Int
    public var channel: CheckChannel
    public var outcome: CheckResult?
    public var occurredAt: Date
    public var entryZone: String
    public var notes: String
    public var followUp: FollowUpTime?
    public var correction: CorrectionReference? = nil
    public struct CorrectionReference: Codable, Equatable, Sendable {
        public let contactID: Int
        public let expectedRevision: Int
        public let legacyDate: String?
    }
    public init(personID: Int, now: Date = Date(), entryZone: String = TimeZone.current.identifier) throws {
        guard personID > 0, TimeZone(identifier: entryZone) != nil else { throw ClientError.invalidInput }
        id = UUID(); self.personID = personID; channel = .phone; outcome = nil
        occurredAt = now; self.entryZone = entryZone; notes = ""; followUp = nil
    }
    public init(correcting record: ContactRecord, now: Date = Date()) throws {
        guard record.personId > 0, record.id > 0, record.revision > 0,
              let channel = CheckChannel(rawValue: record.channel) else { throw ClientError.invalidInput }
        id = UUID(); personID = record.personId; self.channel = channel
        outcome = CheckResult(rawValue: record.outcome); notes = record.notes ?? ""; followUp = nil
        correction = CorrectionReference(contactID: record.id, expectedRevision: record.revision,
                                         legacyDate: record.precision == .date ? record.occurredOn : nil)
        // For date-only records this editing placeholder is neither displayed nor
        // encoded as an event fact. The original date remains the only fact.
        occurredAt = record.occurredAt ?? now; entryZone = record.entryZone ?? TimeZone.current.identifier
    }
    /// Keep the caller's proposed facts, but give their explicitly reviewed
    /// replacement a new operation identity and the current optimistic revision.
    init(continuing draft: ConnectedDraft, afterReviewing record: ContactRecord) throws {
        guard let previous = draft.correction, record.id == previous.contactID,
              record.personId == draft.personID, record.revision > previous.expectedRevision
        else { throw ClientError.invalidInput }
        id = UUID(); personID = draft.personID; channel = draft.channel; outcome = draft.outcome
        occurredAt = draft.occurredAt; entryZone = draft.entryZone; notes = draft.notes
        followUp = draft.followUp
        correction = CorrectionReference(contactID: previous.contactID, expectedRevision: record.revision,
                                         legacyDate: previous.legacyDate)
    }
    public func mutation(now: Date = Date()) throws -> PendingMutation {
        guard let outcome else { throw ClientError.invalidInput }
        guard correction?.legacyDate != nil || occurredAt <= now,
              followUp.map({ $0.dueAt > now }) ?? true else { throw ClientError.invalidInput }
        let facts: CheckFacts
        if let date = correction?.legacyDate { facts = try CheckFacts(legacyDate: date, channel: channel, outcome: outcome, notes: notes) }
        else { facts = try CheckFacts(channel: channel, outcome: outcome, occurredAt: occurredAt, entryZone: entryZone, notes: notes) }
        if let correction {
            return try .correct(personID: personID, contactID: correction.contactID, expectedRevision: correction.expectedRevision,
                                facts: facts, operationID: id, now: now)
        }
        return try .record(personID: personID, facts: facts, followUp: followUp, operationID: id, now: now)
    }
}

public struct JournalSnapshot: Codable, Equatable, Sendable {
    public let scope: AccountScope
    public var draft: ConnectedDraft?
    public var pending: PendingMutation?
    public var contactLinks: [Int: ConnectedContactLink]? = nil
    public var phoneReminders: [Int: ConnectedReminderIntent]? = nil
    public init(scope: AccountScope, draft: ConnectedDraft? = nil, pending: PendingMutation? = nil) {
        self.scope = scope; self.draft = draft; self.pending = pending
    }
}

public struct ConnectedContactLink: Codable, Equatable, Sendable {
    public var contactID: String?
    public var phoneID: String?
    public var emailID: String?
    public var addressID: String?
    public var creationPending: Bool
    public init(contactID: String? = nil, phoneID: String? = nil, emailID: String? = nil, addressID: String? = nil, creationPending: Bool = false) {
        self.contactID = contactID; self.phoneID = phoneID; self.emailID = emailID; self.addressID = addressID; self.creationPending = creationPending
    }
}

@MainActor public protocol SecretVault {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func remove(_ key: String) throws
}

@MainActor public final class DeviceKeychain: SecretVault {
    private let service: String
    public init(service: String = "org.wipost165.buddychecks.connected") { self.service = service }
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false]
    }
    public func read(_ key: String) throws -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw ClientError.journalUnavailable }
        return data
    }
    public func write(_ data: Data, key: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            let result = SecItemAdd(query(key).merging(attributes) { _, new in new } as CFDictionary, nil)
            guard result == errSecSuccess else { throw ClientError.journalUnavailable }
        } else if result != errSecSuccess { throw ClientError.journalUnavailable }
    }
    public func remove(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ClientError.journalUnavailable }
    }
}

@MainActor public protocol JournalPersistence {
    func load(scope: AccountScope) throws -> JournalSnapshot?
    func save(_ snapshot: JournalSnapshot) throws
    func purge(scope: AccountScope) throws
}

@MainActor public final class EncryptedJournal: JournalPersistence {
    private let directory: URL
    private let vault: any SecretVault
    public init(directory: URL, vault: any SecretVault) { self.directory = directory; self.vault = vault }
    func fileURL(_ scope: AccountScope) -> URL { directory.appendingPathComponent(scope.storageKey + ".sealed") }
    private func keyName(_ scope: AccountScope) -> String { "journal." + scope.storageKey }
    public func load(scope: AccountScope) throws -> JournalSnapshot? {
        let file = fileURL(scope)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            guard let key = try vault.read(keyName(scope)), key.count == 32 else { throw ClientError.journalUnavailable }
            let box = try AES.GCM.SealedBox(combined: Data(contentsOf: file))
            let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data(scope.storageKey.utf8))
            let value = try JSONDecoder().decode(JournalSnapshot.self, from: plaintext)
            guard value.scope == scope else { throw ClientError.accountMismatch }
            return value
        } catch { throw ClientError.journalUnavailable }
    }
    public func save(_ snapshot: JournalSnapshot) throws {
        do {
            var folder = directory
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var resource = URLResourceValues(); resource.isExcludedFromBackup = true
            try folder.setResourceValues(resource)
            let name = keyName(snapshot.scope)
            let key: Data
            if let existing = try vault.read(name) { key = existing }
            else {
                // Never replace a missing key for an existing journal.
                guard !FileManager.default.fileExists(atPath: fileURL(snapshot.scope).path) else { throw ClientError.journalUnavailable }
                key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                try vault.write(key, key: name)
            }
            guard key.count == 32 else { throw ClientError.journalUnavailable }
            let plain = try JSONEncoder().encode(snapshot)
            let sealed = try AES.GCM.seal(plain, using: SymmetricKey(data: key), authenticating: Data(snapshot.scope.storageKey.utf8))
            guard let bytes = sealed.combined else { throw ClientError.journalUnavailable }
            #if os(iOS)
            try bytes.write(to: fileURL(snapshot.scope), options: [.atomic, .completeFileProtection])
            #else
            try bytes.write(to: fileURL(snapshot.scope), options: .atomic)
            #endif
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL(snapshot.scope).path)
        } catch { throw ClientError.journalUnavailable }
    }
    public func purge(scope: AccountScope) throws {
        // Destroy the key first. A failed file removal cannot leave decryptable data.
        try vault.remove(keyName(scope))
        let file = fileURL(scope)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}

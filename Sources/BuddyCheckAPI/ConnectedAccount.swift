import Foundation
import Observation
import BuddyCheckCore

@Observable @MainActor public final class ConnectedAccount {
    public let client: BuddyCheckClient
    public private(set) var session: MobileSession?
    public private(set) var journal: SubmissionJournal?
    public private(set) var needsSignIn = false
    public private(set) var hasStoredAccount = false
    public private(set) var reminders: ConnectedReminders?
    public private(set) var reminderRemovalUnconfirmed = false
    private let vault: any SecretVault
    private let persistence: any JournalPersistence
    private var stored: StoredAccount?
    private var generation = UUID()
    // Backgrounding clears visible data but must not discard a rotated secret.
    // Sign-out/account replacement also changes this independent generation.
    private var authorityGeneration = UUID()
    private var isPurging = false
    private var renewal: (id: UUID, task: Task<StoredAccount, Error>)?
    private var authorization: (id: UUID, task: Task<StoredAccount, Error>)?
    private let reminderScheduler: ((String) -> any ReminderScheduling)?
    private let reminderClock: () -> Date
    private let uptime: () -> TimeInterval
    private struct StoredAccount: Codable, Sendable {
        let credential: AccessCredential
        let scope: AccountScope
        var renewal: ExchangeRecovery? = nil
        var authorizationExchangeId: UUID? = nil
    }
    private struct PendingAuthorization: Codable, Sendable {
        let attempt: AuthorizationAttempt
        let callback: URL
        let recovery: ExchangeRecovery
    }
    private let accountKey = "connected.account"
    private let attemptKey = "connected.authorization"
    private let exchangeKey = "connected.authorization.exchange"
    public init(client: BuddyCheckClient, vault: any SecretVault, persistence: any JournalPersistence,
                reminderScheduler: ((String) -> any ReminderScheduling)? = nil,
                reminderClock: @escaping () -> Date = Date.init,
                uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.client = client; self.vault = vault; self.persistence = persistence
        self.reminderScheduler = reminderScheduler; self.reminderClock = reminderClock; self.uptime = uptime
    }
    /// A locked/unreadable Keychain is not evidence that no account exists.
    public static func retainedReminderNamespace(vault: any SecretVault) throws -> String? {
        guard let data = try vault.read("connected.account") else { return nil }
        guard let account = try? JSONDecoder().decode(StoredAccount.self, from: data) else { throw ClientError.journalUnavailable }
        return account.scope.reminderNamespace
    }
    public func restore(now: Date = Date()) async throws {
        guard !isPurging else { throw CancellationError() }
        let current = generation, authority = authorityGeneration
        session = nil; journal = nil
        do {
            try loadStored()
            if let data = try vault.read(exchangeKey) {
                let pending = try JSONDecoder().decode(PendingAuthorization.self, from: data)
                if stored?.authorizationExchangeId == pending.recovery.id {
                    try vault.remove(exchangeKey)
                } else {
                    _ = try await resumeAuthorization(pending, now: now)
                }
            }
            guard stored != nil else { needsSignIn = true; return }
            // Preserve the legacy return behavior for expired pre-upgrade sessions.
            if let stored, !stored.credential.isRemembered, !stored.credential.isValid(at: now) {
                needsSignIn = true; return
            }
            let value = try await validCredential(now: now)
            let (checked, active) = try await checkedSession(value, now: now)
            try currentGeneration(current, authority: authority)
            try publish(checked, account: active)
        } catch { try await fail(error, generation: current, authority: authority) }
    }
    public func beginAuthorization(now: Date = Date(), rememberSession: Bool = false) throws -> AuthorizationAttempt {
        guard !isPurging else { throw CancellationError() }
        try loadStored()
        let attempt = try AuthorizationAttempt(configuration: client.configuration, now: now, rememberSession: rememberSession)
        try vault.write(JSONEncoder().encode(attempt), key: attemptKey)
        try vault.remove(exchangeKey)
        // Any prior late response belongs to the abandoned connection.
        authorityGeneration = UUID(); renewal = nil; authorization = nil
        lock()
        return attempt
    }
    public func finishAuthorization(callback: URL, now: Date = Date()) async throws {
        guard let data = try vault.read(attemptKey), let attempt = try? JSONDecoder().decode(AuthorizationAttempt.self, from: data) else {
            throw ClientError.invalidCallback
        }
        _ = try attempt.code(from: callback, currentConfiguration: client.configuration, now: now)
        let current = generation, authority = authorityGeneration
        do {
            if attempt.rememberSession == true {
                guard let id = attempt.exchangeId else { throw ClientError.invalidCallback }
                let pending = PendingAuthorization(attempt: attempt, callback: callback,
                    recovery: ExchangeRecovery(id: id, startedAt: now, startedUptime: uptime()))
                // Do not consume the only recoverable copy before saving it.
                try vault.write(JSONEncoder().encode(pending), key: exchangeKey)
                try vault.remove(attemptKey)
                let value = try await resumeAuthorization(pending, now: now)
                let (checked, active) = try await checkedSession(value, now: now)
                try currentGeneration(current, authority: authority)
                try publish(checked, account: active)
            } else {
                try vault.remove(attemptKey)
                let credential = try await client.exchange(callback, attempt: attempt, now: now)
                try await acceptAuthority(credential, generation: authority)
                let checked = try await client.session(token: credential.accessToken)
                try currentGeneration(current, authority: authority)
                guard credential.matches(checked) else { throw ClientError.invalidResponse }
                let scope = try AccountScope(configuration: client.configuration, session: checked)
                try await acceptScope(scope, credential: credential)
                let value = StoredAccount(credential: credential, scope: scope)
                try save(value)
                try publish(checked, account: value)
            }
        } catch { try await fail(error, generation: current, authority: authority) }
    }
    // Browser cancellation cannot erase an exchange already sent to the server.
    public func cancelAuthorization() throws { try vault.remove(attemptKey) }

    public func perform<T>(_ action: (BuddyCheckClient, String) async throws -> T, now: Date = Date()) async throws -> T {
        guard session != nil, stored != nil else { throw ClientError.signInRequired }
        let current = generation, authority = authorityGeneration
        do {
            let previous = stored!.credential.accessToken
            var active = try await validCredential(now: now)
            try currentGeneration(current, authority: authority)
            if active.credential.accessToken != previous || !active.credential.matches(session!) {
                let (checked, value) = try await checkedSession(active, now: now)
                try currentGeneration(current, authority: authority)
                try publish(checked, account: value); active = value
            }
            try currentGeneration(current, authority: authority)
            let result: T
            do { result = try await action(client, active.credential.accessToken) }
            catch ClientError.server(401, "expired_session") where active.credential.isRemembered {
                try currentGeneration(current, authority: authority)
                active = try await validCredential(now: now, rejectedToken: active.credential.accessToken)
                let (checked, value) = try await checkedSession(active, now: now, retryExpiry: false)
                try currentGeneration(current, authority: authority)
                try publish(checked, account: value)
                // The caller retains its same draft/immutable operation identity.
                // Only confirmed expiry permits one repeat of the original action.
                result = try await action(client, value.credential.accessToken)
            }
            try currentGeneration(current, authority: authority)
            return result
        } catch { try await fail(error, generation: current, authority: authority) }
    }
    public func lock() { generation = UUID(); session = nil; journal = nil }
    /// False means local sign-out succeeded but remote revocation is unconfirmed.
    public func signOut() async throws -> Bool {
        if stored == nil { try loadStored() }
        let previous = stored
        try await purgeLocal()
        guard let previous else { return true }
        do { try await client.revoke(previous.credential); return true }
        catch { return false }
    }

    private func loadStored() throws {
        guard let data = try vault.read(accountKey) else { return }
        guard let value = try? JSONDecoder().decode(StoredAccount.self, from: data) else { throw ClientError.journalUnavailable }
        guard value.scope.issuer == client.configuration.issuer else { throw ClientError.accountMismatch }
        stored = value; hasStoredAccount = true
    }
    private func save(_ value: StoredAccount) throws {
        try vault.write(JSONEncoder().encode(value), key: accountKey)
        stored = value; hasStoredAccount = true
    }
    private func validCredential(now: Date, rejectedToken: String? = nil) async throws -> StoredAccount {
        if let renewal { return try await renewal.task.value }
        guard var value = stored else { throw ClientError.signInRequired }
        let rejected = rejectedToken == value.credential.accessToken
        if value.renewal == nil, value.credential.isValid(at: now), !rejected { return value }
        guard value.credential.isRemembered else { throw ClientError.server(status: 401, code: "expired_session") }
        if value.renewal == nil {
            value.renewal = ExchangeRecovery(id: UUID(), startedAt: now, startedUptime: uptime())
            try save(value)
        }
        let recovery = value.renewal!
        let timeout = try recovery.timeout(now: now, uptime: uptime())
        let input = value, authority = authorityGeneration, id = UUID()
        let task = Task { @MainActor in
            let credential = try await self.client.renew(input.credential, exchangeID: recovery.id, now: now, timeout: timeout)
            try await self.acceptAuthority(credential, generation: authority)
            let replacement = StoredAccount(credential: credential, scope: input.scope,
                                           authorizationExchangeId: input.authorizationExchangeId)
            // Save before /session or any data request. A failed save leaves the
            // original input + exchange ID available for bounded recovery.
            try self.save(replacement)
            return replacement
        }
        renewal = (id, task)
        defer { if renewal?.id == id { renewal = nil } }
        return try await task.value
    }
    private func resumeAuthorization(_ pending: PendingAuthorization, now: Date) async throws -> StoredAccount {
        if let authorization { return try await authorization.task.value }
        let timeout = try pending.recovery.timeout(now: now, uptime: uptime())
        let authority = authorityGeneration, id = UUID()
        let task = Task { @MainActor in
            let credential = try await self.client.exchange(pending.callback, attempt: pending.attempt, now: now, timeout: timeout)
            try await self.acceptAuthority(credential, generation: authority)
            let scope = try AccountScope(configuration: self.client.configuration, credential: credential)
            try await self.acceptScope(scope, credential: credential)
            let value = StoredAccount(credential: credential, scope: scope, authorizationExchangeId: pending.recovery.id)
            try self.save(value)
            try self.vault.remove(self.exchangeKey)
            return value
        }
        authorization = (id, task)
        defer { if authorization?.id == id { authorization = nil } }
        return try await task.value
    }
    private func checkedSession(_ value: StoredAccount, now: Date, retryExpiry: Bool = true) async throws -> (MobileSession, StoredAccount) {
        let authority = authorityGeneration
        var active = value
        let checked: MobileSession
        do { checked = try await client.session(token: active.credential.accessToken) }
        catch ClientError.server(401, "expired_session") where retryExpiry && active.credential.isRemembered {
            guard authority == authorityGeneration else { throw CancellationError() }
            active = try await validCredential(now: now, rejectedToken: active.credential.accessToken)
            checked = try await client.session(token: active.credential.accessToken)
        }
        guard active.credential.matches(checked) else { throw ClientError.invalidResponse }
        guard try AccountScope(configuration: client.configuration, session: checked) == active.scope else { throw ClientError.accountMismatch }
        return (checked, active)
    }
    private func publish(_ checked: MobileSession, account: StoredAccount) throws {
        // A submission may hold the current journal instance while access renews.
        if journal == nil { journal = try SubmissionJournal(scope: account.scope, persistence: persistence) }
        session = checked; needsSignIn = false
        configureReminders(account.scope)
    }
    private func acceptAuthority(_ credential: AccessCredential, generation: UUID) async throws {
        guard generation == authorityGeneration else {
            // A sign-out may race a successful exchange. Revoke the late pair,
            // including when no prior token was available during sign-out.
            try? await client.revoke(credential)
            throw CancellationError()
        }
    }
    private func acceptScope(_ scope: AccountScope, credential: AccessCredential) async throws {
        guard stored.map({ $0.scope == scope }) ?? true else {
            try? await client.revoke(credential)
            throw ClientError.accountMismatch
        }
    }
    private func configureReminders(_ scope: AccountScope) {
        guard reminders == nil, let reminderScheduler else { return }
        reminders = ConnectedReminders(account: self, scope: scope,
                                      scheduler: reminderScheduler(scope.reminderNamespace), now: reminderClock)
    }
    private func fail(_ error: Error, generation: UUID, authority: UUID) async throws -> Never {
        guard authority == authorityGeneration else { throw CancellationError() }
        if let failure = error as? ClientError, failure.confirmsRevocation {
            // Confirmed loss of access also purges if the app went to background.
            try await purgeLocal()
        } else {
            try currentGeneration(generation, authority: authority)
            if let failure = error as? ClientError, failure.requiresSignIn { lock(); needsSignIn = true }
        }
        throw error
    }
    private func purgeLocal() async throws {
        guard !isPurging else { throw CancellationError() }
        isPurging = true
        defer { isPurging = false }
        let existingJournal = journal
        authorityGeneration = UUID(); renewal = nil; authorization = nil
        lock(); needsSignIn = true
        if reminders == nil, let stored { configureReminders(stored.scope) }
        if let reminders { reminderRemovalUnconfirmed = !(await reminders.purge()) }
        reminders = nil
        if let existingJournal { try existingJournal.purge() }
        else if let stored { try persistence.purge(scope: stored.scope) }
        try vault.remove(attemptKey)
        try vault.remove(exchangeKey)
        try vault.remove(accountKey)
        stored = nil; hasStoredAccount = false
    }
    private func currentGeneration(_ value: UUID, authority: UUID) throws {
        guard value == generation, authority == authorityGeneration else { throw CancellationError() }
    }
}

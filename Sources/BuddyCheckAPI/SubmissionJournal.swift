import Foundation
import Observation

/// Owns only the caller's unfinished facts and one immutable submission. All
/// directory/history/export responses remain outside this persisted state.
@Observable @MainActor public final class SubmissionJournal {
    public private(set) var snapshot: JournalSnapshot
    public private(set) var lastReceipt: MutationReceipt?
    public private(set) var isSubmitting = false
    public private(set) var rejection: ClientError?
    private let persistence: any JournalPersistence
    private var generation = UUID()
    public init(scope: AccountScope, persistence: any JournalPersistence) throws {
        self.persistence = persistence
        snapshot = try persistence.load(scope: scope) ?? JournalSnapshot(scope: scope)
        guard snapshot.scope == scope else { throw ClientError.accountMismatch }
    }
    public func saveDraft(_ draft: ConnectedDraft) throws {
        guard snapshot.pending == nil, !isSubmitting,
              snapshot.draft.map({ $0.id == draft.id }) ?? true else { throw ClientError.unfinishedOperation }
        var next = snapshot; next.draft = draft
        try publish(next)
    }
    public func discardDraft() throws {
        guard snapshot.pending == nil, !isSubmitting else { throw ClientError.unfinishedOperation }
        var next = snapshot; next.draft = nil
        try publish(next)
    }
    public func rememberContact(personID: Int, link: ConnectedContactLink) throws {
        guard personID > 0, link.contactID.map({ !$0.isEmpty }) ?? true else { throw ClientError.invalidInput }
        var next = snapshot
        if next.contactLinks == nil { next.contactLinks = [:] }
        next.contactLinks?[personID] = link
        try publish(next)
    }
    public func rememberReminder(_ intent: ConnectedReminderIntent) throws {
        guard intent.followUpID > 0, intent.revision >= 0, intent.due.timeIntervalSince1970.isFinite,
              intent.snoozedUntil.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
              snapshot.phoneReminders?[intent.followUpID].map({ $0.id == intent.id }) ?? true,
              !(snapshot.phoneReminders ?? [:]).contains(where: { $0.key != intent.followUpID && $0.value.id == intent.id })
        else { throw ClientError.invalidInput }
        guard snapshot.phoneReminders?[intent.followUpID] != intent else { return }
        var next = snapshot
        if next.phoneReminders == nil { next.phoneReminders = [:] }
        next.phoneReminders?[intent.followUpID] = intent
        try publish(next)
    }
    public func removeReminder(followUpID: Int) throws {
        guard snapshot.phoneReminders?[followUpID] != nil else { return }
        var next = snapshot; next.phoneReminders?[followUpID] = nil
        try publish(next)
    }
    public func prepare(_ operation: PendingMutation) throws {
        guard !isSubmitting, snapshot.pending == nil,
              snapshot.draft.map({ $0.id == operation.id && $0.personID == operation.personID }) ?? true
        else { throw ClientError.unfinishedOperation }
        var next = snapshot; next.pending = operation
        try publish(next)
        lastReceipt = nil
        rejection = nil
    }
    /// Recover first, including on the first send. A receipt 404 never creates
    /// a replacement operation. Current recipient authority is checked before
    /// the original body is submitted or retried.
    public func reconcile(client: BuddyCheckClient, token: String) async throws -> MutationReceipt {
        rejection = nil
        do { return try await submitPending(client: client, token: token) }
        catch {
            if let failure = error as? ClientError {
                switch failure {
                case .server(422, "invalid_request"), .server(409, "stale_revision"), .server(409, "follow_up_closed"):
                    rejection = failure
                default: break
                }
            }
            throw error
        }
    }
    /// Only a definite rejection can be discarded here. Unknown, missing and
    /// payload-conflicting receipts must keep their original operation identity.
    public func discardRejectedSubmission() throws {
        guard rejection != nil, !isSubmitting else { throw ClientError.unfinishedOperation }
        var next = snapshot; next.pending = nil; next.draft = nil
        try publish(next)
        rejection = nil
    }
    public var canReviewStaleCorrection: Bool {
        guard rejection == .server(status: 409, code: "stale_revision"), !isSubmitting,
              let pending = snapshot.pending, let draft = snapshot.draft,
              case .correction(let contactID) = pending.route,
              let reference = draft.correction else { return false }
        return pending.id == draft.id && pending.personID == draft.personID
            && reference.contactID == contactID && reference.expectedRevision == pending.expectedRevision
    }
    /// Called only after the current server facts have been shown and the caller
    /// chooses to continue. Nothing is submitted until another explicit Save.
    @discardableResult public func continueCorrection(afterReviewing record: ContactRecord) throws -> ConnectedDraft {
        guard canReviewStaleCorrection, let draft = snapshot.draft else { throw ClientError.unfinishedOperation }
        let replacement = try ConnectedDraft(continuing: draft, afterReviewing: record)
        var next = snapshot; next.pending = nil; next.draft = replacement
        try publish(next)
        rejection = nil
        return replacement
    }
    private func submitPending(client: BuddyCheckClient, token: String) async throws -> MutationReceipt {
        guard !isSubmitting, let operation = snapshot.pending,
              client.configuration.issuer == snapshot.scope.issuer else { throw ClientError.invalidInput }
        isSubmitting = true
        let attempt = generation
        defer { isSubmitting = false }
        let receipt: MutationReceipt
        do {
            receipt = try await client.receipt(operationID: operation.id, token: token)
        } catch ClientError.server(404, "not_found") {
            try ensureCurrent(attempt)
            _ = try await client.person(operation.personID, token: token)
            try ensureCurrent(attempt)
            // Recency exclusions do not erase a check that actually happened.
            // The mutation endpoint remains authoritative for pause/access.
            receipt = try await client.submit(operation, token: token)
        }
        try ensureCurrent(attempt)
        guard operation.matches(receipt) else { throw ClientError.invalidResponse }
        // If disk fails here, retain the original operation. The next retry
        // recovers the receipt instead of issuing another logical submission.
        var next = snapshot; next.pending = nil
        if next.draft?.id == operation.id { next.draft = nil }
        try publish(next)
        lastReceipt = receipt
        return receipt
    }
    public func purge() throws {
        generation = UUID()
        snapshot = JournalSnapshot(scope: snapshot.scope); lastReceipt = nil; rejection = nil
        try persistence.purge(scope: snapshot.scope)
    }
    private func ensureCurrent(_ value: UUID) throws {
        guard value == generation else { throw CancellationError() }
    }
    private func publish(_ value: JournalSnapshot) throws {
        try persistence.save(value)
        snapshot = value
    }
}

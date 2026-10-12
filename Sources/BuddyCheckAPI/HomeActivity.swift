import Foundation

extension BuddyCheckClient {
    /// These endpoints contain only the signed-in caller's records. Complete
    /// pagination before ranking: page order is not a due-time/event-time promise.
    /// Returned summaries live in the UI only, never in the protected journal.
    public func nextOpenFollowUp(token: String) async throws -> FollowUpRecord? {
        var records: [Int: FollowUpRecord] = [:]
        var cursor: String?
        var seen = Set<String>()
        repeat {
            try Task.checkCancellation()
            let page = try await followUps(cursor: cursor, token: token)
            for record in page.items {
                if let old = records[record.id], old.revision > record.revision { continue }
                records[record.id] = record
            }
            cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw ClientError.invalidResponse }
        } while cursor != nil
        return records.values.filter { $0.status == .open }.min {
            $0.dueAt == $1.dueAt ? $0.id < $1.id : $0.dueAt < $1.dueAt
        }
    }

    public func recentChecks(token: String) async throws -> [ContactRecord] {
        var records: [Int: ContactRecord] = [:]
        var cursor: String?
        var seen = Set<String>()
        repeat {
            try Task.checkCancellation()
            let page = try await history(cursor: cursor, token: token)
            for record in page.items {
                if let old = records[record.id], old.revision > record.revision { continue }
                records[record.id] = record
            }
            cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw ClientError.invalidResponse }
        } while cursor != nil
        // Recent means recently recorded (including corrections), so a backdated
        // check remains discoverable after the caller has just saved it.
        return Array(records.values.sorted {
            $0.recordedAt == $1.recordedAt ? $0.id > $1.id : $0.recordedAt > $1.recordedAt
        }.prefix(3))
    }

    public func latestContact(_ previous: ContactRecord, token: String) async throws -> ContactRecord {
        _ = try await person(previous.personId, token: token)
        var cursor: String?
        var seen = Set<String>()
        var latest: ContactRecord?
        repeat {
            try Task.checkCancellation()
            let page = try await revisions(contactID: previous.id, cursor: cursor, token: token)
            for record in page.items where record.id == previous.id {
                guard record.personId == previous.personId else { throw ClientError.invalidResponse }
                if record.revision > (latest?.revision ?? 0) { latest = record }
            }
            cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw ClientError.invalidResponse }
        } while cursor != nil
        guard let latest, latest.revision >= previous.revision else { throw ClientError.invalidResponse }
        return latest
    }
}

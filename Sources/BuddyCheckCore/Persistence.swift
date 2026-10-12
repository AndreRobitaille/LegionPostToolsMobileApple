import Foundation

@MainActor public protocol SnapshotPersistence {
    func load() throws -> LocalSnapshot?
    func save(_ snapshot: LocalSnapshot) throws
}

@MainActor public final class JSONSnapshotPersistence: SnapshotPersistence {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load() throws -> LocalSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let data = try Data(contentsOf: fileURL)
            // Read the version first, even if newer formats have changed required fields.
            struct Version: Decodable { let formatVersion: Int }
            guard [1, 2, 3, 4, 5].contains(try decoder.decode(Version.self, from: data).formatVersion) else {
                throw WorkflowError.unsupportedFormat
            }
            let snapshot = try decoder.decode(LocalSnapshot.self, from: data)
            guard Set(snapshot.reminderIDs).count == snapshot.reminderIDs.count,
                  snapshot.reminderSnoozes.allSatisfy({ snapshot.reminderIDs.contains($0.key) && $0.value.timeIntervalSince1970.isFinite }),
                  snapshot.reminderIDs.allSatisfy({ id in snapshot.followUps.contains { $0.id == id } }),
                  Set(snapshot.suggestionSnoozes.map(\.personID)).count == snapshot.suggestionSnoozes.count,
                  Set(snapshot.contactLinks.map(\.identity)).count == snapshot.contactLinks.count,
                  snapshot.contactLinks.allSatisfy({ $0.creationPending || ($0.contactID?.isEmpty == false) }),
                  Set(snapshot.checks.map(\.id)).count == snapshot.checks.count,
                  Set(snapshot.followUps.map(\.id)).count == snapshot.followUps.count,
                  snapshot.followUps.allSatisfy({ item in snapshot.checks.contains { $0.id == item.checkID && $0.personID == item.personID } }) else {
                throw WorkflowError.damagedStorage
            }
            return snapshot
        } catch let error as WorkflowError { throw error }
        catch { throw WorkflowError.damagedStorage }
    }
    public func save(_ snapshot: LocalSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }
}

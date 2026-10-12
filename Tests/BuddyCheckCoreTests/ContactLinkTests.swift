import Foundation
import Testing
@testable import BuddyCheckCore

@MainActor private final class LinkPersistence: SnapshotPersistence {
    var value: LocalSnapshot?
    var fail = false
    func load() throws -> LocalSnapshot? { value }
    func save(_ snapshot: LocalSnapshot) throws {
        if fail { throw CocoaError(.fileWriteOutOfSpace) }
        value = snapshot
    }
}
@Suite @MainActor struct ContactLinkTests {
    let person = SyntheticDirectory.people[0]
    @Test func sourceQualifiedIdentityNeverMatchesNamesOrSharedNumbers() throws {
        let persistence = LinkPersistence(); let store = CheckStore(persistence: persistence)
        var original = person; original.externalReference = ExternalReference(source: "post-a", identifier: "42")
        try store.rememberContact(person: original, contactID: "device-1", managed: .init())
        var otherPost = original; otherPost.externalReference = ExternalReference(source: "post-b", identifier: "42")
        #expect(store.contactLink(for: otherPost) == nil)
        let sameSource = Person(id: UUID(), firstName: "Robert", lastName: "Miller", externalReference: original.externalReference, phone: original.phone, isSynthetic: true)
        #expect(store.contactLink(for: sameSource)?.contactID == "device-1")
        let household = Person(id: UUID(), firstName: "Robert", lastName: "Miller", phone: original.phone, isSynthetic: true)
        #expect(store.contactLink(for: household) == nil)
    }
    @Test func interruptedCreationSurvivesReloadAndRequiresExplicitChoice() throws {
        let persistence = LinkPersistence(); let store = CheckStore(persistence: persistence)
        try store.beginContactCreation(person: person)
        let reopened = CheckStore(persistence: persistence)
        #expect(reopened.contactLink(for: person)?.creationPending == true)
        #expect(throws: ContactsError.creationUnresolved) { try reopened.beginContactCreation(person: person) }
        try reopened.cancelContactCreation(person: person)
        #expect(reopened.contactLink(for: person) == nil)
        try reopened.beginContactCreation(person: person)
        try reopened.rememberContact(person: person, contactID: "saved-contact", managed: .init(phoneID: "post-phone"))
        #expect(reopened.contactLink(for: person)?.creationPending == false)
        #expect(throws: ContactsError.creationUnresolved) { try reopened.beginContactCreation(person: person) }
    }
    @Test func failedLinkSaveRetainsPendingCreationAndRetryDoesNotCreateAgain() throws {
        let persistence = LinkPersistence(); let store = CheckStore(persistence: persistence)
        try store.beginContactCreation(person: person)
        persistence.fail = true
        #expect(throws: CocoaError.self) { try store.rememberContact(person: person, contactID: "already-created", managed: .init()) }
        #expect(store.contactLink(for: person)?.creationPending == true)
        persistence.fail = false
        try store.rememberContact(person: person, contactID: "already-created", managed: .init())
        #expect(store.snapshot.contactLinks.count == 1)
    }
    @Test func cancellingReplacementRetainsPreviousAssociation() throws {
        let store = CheckStore(persistence: LinkPersistence())
        try store.rememberContact(person: person, contactID: "original", managed: .init(emailID: "original-email"))
        try store.beginContactCreation(person: person, explicitlyCreateAnother: true)
        try store.cancelContactCreation(person: person)
        #expect(store.contactLink(for: person)?.contactID == "original")
        #expect(store.contactLink(for: person)?.managed.emailID == "original-email")
        #expect(store.contactLink(for: person)?.creationPending == false)
    }
    @Test func readsLegacySnapshotWithoutLosingCheckData() throws {
        let persistence = LinkPersistence(); let store = CheckStore(persistence: persistence)
        let id = try store.begin(personID: person.id, origin: .manual, timeZone: "America/Chicago")
        try store.updateDraft(id: id) { $0.outcome = .connected }
        try store.saveDraft(id: id, includeFollowUp: false)
        let encoder = JSONEncoder()
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(store.snapshot)) as? [String: Any])
        object["formatVersion"] = 1; object.removeValue(forKey: "contactLinks")
        let migrated = try JSONDecoder().decode(LocalSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(migrated.formatVersion == 5)
        #expect(migrated.checks == store.snapshot.checks)
        #expect(migrated.contactLinks.isEmpty)
    }
    @Test func realExportRequiresAnExplicitPermit() throws {
        #expect(throws: ContactsError.exportNotPermitted) { try ContactExport(person: person, post: .synthetic, permitted: false) }
    }
}

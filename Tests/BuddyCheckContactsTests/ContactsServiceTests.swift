import Foundation
import Contacts
import Testing
import BuddyCheckCore
@testable import BuddyCheckContacts

@MainActor private final class FakeContactsBackend: ContactsBackend {
    var access = ContactsAccess.notDetermined
    var nextAccess = ContactsAccess.limited
    var contact = CNMutableContact()
    var missing = false
    var failSave = false
    var saveError: NSError?
    var fetches = 0
    var requestThrows = false
    var requests = 0
    var saves = 0
    func requestAccess() async throws {
        requests += 1; access = nextAccess
        if requestThrows { throw CocoaError(.fileReadNoPermission) }
    }
    func fetch(id: String, keys: [any CNKeyDescriptor]) throws -> CNContact {
        fetches += 1
        if missing { throw CocoaError(.fileNoSuchFile) }
        return contact.copy() as! CNContact
    }
    func save(_ contact: CNMutableContact) throws {
        if let saveError { throw saveError }
        if failSave { throw CocoaError(.fileWriteOutOfSpace) }
        saves += 1; self.contact = contact.mutableCopy() as! CNMutableContact
    }
}
@Suite @MainActor struct ContactsServiceTests {
    @Test(arguments: [false, true]) func denialDoesNotFetchOrKeepPrompting(requestThrows: Bool) async throws {
        let backend = FakeContactsBackend(); backend.nextAccess = .denied; backend.requestThrows = requestThrows
        let service = AppleContactsService(backend: backend)
        do { try await service.requestAccess(); Issue.record("Expected denied access") } catch { #expect(error as? ContactsError == .accessDenied) }
        do { try await service.requestAccess(); Issue.record("Expected denied access") } catch { #expect(error as? ContactsError == .accessDenied) }
        #expect(backend.requests == 1)
        #expect(throws: ContactsError.accessDenied) { try service.fetch(id: "selected") }
        #expect(backend.fetches == 0)
    }
    @Test func limitedAccessAllowsOnlySelectedFetchAndRevocationStopsSave() async throws {
        let backend = FakeContactsBackend(); let service = AppleContactsService(backend: backend)
        try await service.requestAccess()
        let existing = try service.fetch(id: backend.contact.identifier)
        let exported = try ContactExport(person: SyntheticDirectory.people[0], post: .synthetic, permitted: true)
        let plan = ContactUpdatePlan(existing: existing, proposed: exported)
        backend.access = .denied
        #expect(throws: ContactsError.accessDenied) { try service.apply(plan, selected: Set(ExportField.allCases)) }
        #expect(backend.saves == 0)
        backend.access = .limited
        backend.missing = true
        #expect(throws: ContactsError.unavailable) { try service.fetch(id: "deleted-or-unshared") }
    }
    @Test func failedSaveLeavesContactUnchangedAndRetrySavesOnce() throws {
        let backend = FakeContactsBackend(); backend.access = .authorized
        let service = AppleContactsService(backend: backend)
        let before = try service.fetch(id: backend.contact.identifier)
        let plan = ContactUpdatePlan(existing: before, proposed: try ContactExport(person: SyntheticDirectory.people[0], post: .synthetic, permitted: true))
        backend.failSave = true
        #expect(throws: ContactsError.saveFailed) { try service.apply(plan, selected: [.company]) }
        #expect(try service.fetch(id: before.id) == before)
        backend.failSave = false
        let saved = try service.apply(plan, selected: [.company])
        #expect(saved.company == "American Legion Post 165")
        #expect(backend.saves == 1)
        #expect(throws: ContactsError.changedDuringReview) { try service.apply(plan, selected: [.company]) }
        #expect(backend.saves == 1)
    }

    @Test func explicitSaveNormalizesLegacyLabelsAndMatchingRevisitDoesNotWrite() throws {
        let backend = FakeContactsBackend(); backend.access = .authorized
        let proposed = try ContactExport(person: SyntheticDirectory.people[0], post: .synthetic, permitted: true)
        backend.contact = ContactMapping.newContact(proposed)
        backend.contact.phoneNumbers = [backend.contact.phoneNumbers[0].settingLabel("Post 165")]
        let managed = ManagedContactFields(phoneID: backend.contact.phoneNumbers[0].identifier)
        let service = AppleContactsService(backend: backend)
        let before = try service.fetch(id: backend.contact.identifier)
        let plan = ContactUpdatePlan(existing: before, proposed: proposed, managed: managed)
        #expect(backend.saves == 0)
        #expect(plan.changes.isEmpty && plan.hasUpdates(selected: []))
        backend.failSave = true
        #expect(throws: ContactsError.saveFailed) { try service.apply(plan, selected: []) }
        #expect(try service.fetch(id: before.id) == before)
        backend.failSave = false
        let saved = try service.apply(plan, selected: [])
        #expect(saved.phones[0].label == CNLabelHome)
        #expect(saved.phones[0].id == managed.phoneID)
        #expect(backend.saves == 1)
        let repeated = ContactUpdatePlan(existing: saved, proposed: proposed, managed: managed)
        _ = try service.apply(repeated, selected: [])
        #expect(backend.saves == 1)
    }

    @Test(arguments: [CNError.Code.recordNotWritable.rawValue, CNError.Code.parentContainerNotWritable.rawValue])
    func readOnlyAccountFailurePreservesContactAndOffersDifferentAccount(code: Int) throws {
        let backend = FakeContactsBackend(); backend.access = .limited
        backend.contact.organizationName = "Read-only Synthetic Account"
        let service = AppleContactsService(backend: backend)
        let before = try service.fetch(id: backend.contact.identifier)
        let plan = ContactUpdatePlan(existing: before, proposed: try ContactExport(person: SyntheticDirectory.people[0], post: .synthetic, permitted: true))
        backend.saveError = NSError(domain: CNErrorDomain, code: code)
        #expect(throws: ContactsError.readOnly) { try service.apply(plan, selected: [.company]) }
        #expect(try service.fetch(id: before.id) == before)
        #expect(backend.saves == 0)
        // An unrelated domain using the same numeric code is still a generic failure.
        backend.saveError = NSError(domain: NSCocoaErrorDomain, code: code)
        #expect(throws: ContactsError.saveFailed) { try service.apply(plan, selected: [.company]) }
    }
}

import Foundation
import Contacts
import Testing
import BuddyCheckCore
@testable import BuddyCheckContacts

struct ContactMappingTests {
    let person = SyntheticDirectory.people[0]
    func export() throws -> ContactExport { try ContactExport(person: person, post: .synthetic, permitted: true) }

    @Test func createsOnlyAllowedFieldsAndUsesPostCompany() throws {
        let contact = ContactMapping.newContact(try export())
        #expect(contact.givenName == "Robert")
        #expect(contact.familyName == "Miller")
        #expect(contact.organizationName == "American Legion Post 165")
        #expect(contact.phoneNumbers.first?.value.stringValue == "+12025550101")
        #expect(contact.phoneNumbers.first?.label == CNLabelHome)
        #expect(contact.emailAddresses.first?.value as String? == "robert.miller@example.org")
        #expect(contact.emailAddresses.first?.label == CNLabelHome)
        #expect(contact.postalAddresses.first?.value.street == "100 Example Street")
        #expect(contact.postalAddresses.first?.value.city == "Two Rivers")
        #expect(contact.postalAddresses.first?.value.state == "WI")
        #expect(contact.postalAddresses.first?.value.postalCode == "54241")
        #expect(contact.postalAddresses.first?.value.isoCountryCode == "US")
        #expect(contact.postalAddresses.first?.label == CNLabelHome)
        #expect(contact.birthday == nil)
        #expect(contact.urlAddresses.isEmpty)
    }

    @Test func conflictingPersonalFieldsAreNotSelectedAndUnrelatedFieldsSurvive() throws {
        let existing = CNMutableContact()
        existing.givenName = "Bob"; existing.familyName = "Miller"; existing.organizationName = "Personal employer"
        existing.nickname = "Bob M"; existing.birthday = DateComponents(year: 1950, month: 1, day: 2)
        existing.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: "https://example.org/personal" as NSString)]
        existing.phoneNumbers = [CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "+12025550199"))]
        let plan = ContactUpdatePlan(existing: ContactMapping.project(existing), proposed: try export())
        #expect(!plan.initialSelection.contains(.firstName))
        #expect(!plan.initialSelection.contains(.company))
        #expect(!plan.initialSelection.contains(.phone))
        #expect(plan.initialSelection.contains(.email))
        let updated = try ContactMapping.applying(plan, selected: [.company, .phone], to: existing)
        #expect(updated.givenName == "Bob")
        #expect(updated.organizationName == "American Legion Post 165")
        #expect(updated.phoneNumbers.count == 2)
        #expect(updated.phoneNumbers.first?.identifier == existing.phoneNumbers.first?.identifier)
        #expect(updated.phoneNumbers.first?.label == CNLabelHome)
        #expect(updated.phoneNumbers.first?.value.stringValue == "+12025550199")
        #expect(updated.phoneNumbers.last?.label == CNLabelHome)
        #expect(updated.nickname == "Bob M")
        #expect(updated.birthday == existing.birthday)
        #expect(updated.urlAddresses == existing.urlAddresses)
        #expect(existing.organizationName == "Personal employer")
    }

    @Test func replacesOnlyExplicitlyLinkedValueAndPreservesItsLabel() throws {
        let existing = CNMutableContact()
        existing.phoneNumbers = [CNLabeledValue(label: "Personal", value: CNPhoneNumber(stringValue: "+12025550199")),
                                 CNLabeledValue(label: "Custom Post label", value: CNPhoneNumber(stringValue: "+12025550100"))]
        let linkedID = existing.phoneNumbers[1].identifier
        let plan = ContactUpdatePlan(existing: ContactMapping.project(existing), proposed: try export(), managed: .init(phoneID: linkedID))
        let change = try #require(plan.changes.first { $0.field == .phone })
        #expect(change.replacingValueID == linkedID)
        #expect(!change.addsValue)
        let updated = try ContactMapping.applying(plan, selected: [.phone], to: existing)
        #expect(updated.phoneNumbers.count == 2)
        #expect(updated.phoneNumbers[1].identifier == linkedID)
        #expect(updated.phoneNumbers[1].label == "Custom Post label")
        #expect(updated.phoneNumbers[1].value.stringValue == person.phone)
        #expect(updated.phoneNumbers[0].value.stringValue == "+12025550199")
        let saved = ContactMapping.project(updated)
        #expect(plan.linkedFields(after: saved, selected: [.phone]).phoneID == linkedID)
        let repeated = ContactUpdatePlan(existing: saved, proposed: try export(), managed: .init(phoneID: linkedID))
        #expect(!repeated.changes.contains { $0.field == .phone })
    }

    @Test func missingPostFieldsDoNotClearExistingValues() throws {
        let existing = ContactMapping.newContact(try export())
        let emptyPerson = Person(id: UUID(), firstName: "", lastName: "", phone: "   ", email: "", isSynthetic: true)
        let proposed = try ContactExport(person: emptyPerson, post: .synthetic, permitted: true)
        let plan = ContactUpdatePlan(existing: ContactMapping.project(existing), proposed: proposed)
        #expect(plan.changes.isEmpty)
        let updated = try ContactMapping.applying(plan, selected: Set(ExportField.allCases), to: existing)
        #expect(updated.givenName == "Robert")
        #expect(updated.phoneNumbers == existing.phoneNumbers)
        #expect(updated.emailAddresses == existing.emailAddresses)
        #expect(updated.postalAddresses == existing.postalAddresses)
    }

    @Test func refusesStaleReviewButPreservesUnrelatedConcurrentEdit() throws {
        let existing = ContactMapping.newContact(try export())
        let plan = ContactUpdatePlan(existing: ContactMapping.project(existing), proposed: try export())
        existing.organizationName = "Changed elsewhere"
        #expect(throws: ContactsError.changedDuringReview) { try ContactMapping.applying(plan, selected: [.company], to: existing) }
        existing.organizationName = "American Legion Post 165"
        existing.nickname = "Updated elsewhere"
        let updated = try ContactMapping.applying(plan, selected: [], to: existing)
        #expect(updated.nickname == "Updated elsewhere")
    }
    @Test func formattedPhoneDoesNotAddADuplicate() throws {
        let existing = CNMutableContact()
        existing.phoneNumbers = [CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "+1 (202) 555-0101"))]
        let plan = ContactUpdatePlan(existing: ContactMapping.project(existing), proposed: try export())
        #expect(!plan.changes.contains { $0.field == .phone })
        #expect(plan.linkedFields(after: ContactMapping.project(existing), selected: []).phoneID == existing.phoneNumbers[0].identifier)
        #expect(!phoneValuesMatch("+1 202 555 0101 ext 4", "+1 202 555 0101"))
    }

    @Test func creationLinksOnlyPostValuesRetainedInNativeEditor() throws {
        let proposed = try export()
        let created = ContactMapping.newContact(proposed)
        // The caller changes the prefilled email before native Save.
        created.emailAddresses = [CNLabeledValue(label: "Personal", value: "personal@example.test" as NSString)]
        let saved = ContactMapping.project(created)
        let creation = ContactUpdatePlan(existing: saved, proposed: proposed)
        let managed = creation.linkedFields(after: saved, selected: [])
        #expect(managed.phoneID == created.phoneNumbers.first?.identifier)
        #expect(managed.addressID == created.postalAddresses.first?.identifier)
        #expect(managed.emailID == nil)
        var changed = person
        changed.phone = "+12025550188"; changed.email = "new-post@example.test"
        let later = ContactUpdatePlan(existing: saved,
                                     proposed: try ContactExport(person: changed, post: .synthetic, permitted: true), managed: managed)
        let phone = try #require(later.changes.first { $0.field == .phone })
        #expect(phone.replacingValueID == managed.phoneID)
        #expect(!phone.addsValue)
        let email = try #require(later.changes.first { $0.field == .email })
        #expect(email.addsValue && email.replacingValueID == nil)
        let updated = try ContactMapping.applying(later, selected: [.phone, .email], to: created)
        #expect(updated.phoneNumbers.count == 1)
        #expect(updated.phoneNumbers[0].identifier == managed.phoneID)
        #expect(updated.emailAddresses.map { $0.value as String } == ["personal@example.test", "new-post@example.test"])
        #expect(updated.emailAddresses.map(\.label) == ["Personal", CNLabelHome])
    }

    @Test func legacyLinkedEmailUsesHomeOnSaveWithoutASeparateChoiceOrDuplicate() throws {
        let existing = ContactMapping.newContact(try export())
        let legacy = existing.emailAddresses[0].settingLabel("Post 165")
        let personal = CNLabeledValue(label: "Post 165", value: "other@example.test" as NSString)
        existing.emailAddresses = [legacy, personal]
        let managed = ManagedContactFields(emailID: legacy.identifier)
        let plan = ContactUpdatePlan(existing: ContactMapping.project(existing), proposed: try export(), managed: managed)
        #expect(plan.changes.isEmpty)
        #expect(plan.homeLabelFields == [.email])
        #expect(!plan.initialSelection.contains(.email))
        let updated = try ContactMapping.applying(plan, selected: [], to: existing)
        #expect(updated.emailAddresses.count == 2)
        #expect(updated.emailAddresses[0].identifier == legacy.identifier)
        #expect(updated.emailAddresses[0].value == legacy.value)
        #expect(updated.emailAddresses[0].label == CNLabelHome)
        #expect(updated.emailAddresses[1] == personal)
        let repeated = ContactUpdatePlan(existing: ContactMapping.project(updated), proposed: try export(), managed: managed)
        #expect(repeated.changes.isEmpty)
        #expect(!repeated.hasUpdates(selected: []))
    }

    @Test(arguments: ["Post 165", "Personal"])
    func changingLinkedEmailMigratesOnlyTheOldPostLabel(label: String) throws {
        let existing = ContactMapping.newContact(try export())
        existing.emailAddresses = [CNLabeledValue(label: label, value: "old@example.test" as NSString)]
        let identifier = existing.emailAddresses[0].identifier
        let plan = ContactUpdatePlan(existing: ContactMapping.project(existing), proposed: try export(), managed: .init(emailID: identifier))
        let updated = try ContactMapping.applying(plan, selected: [.email], to: existing)
        #expect(updated.emailAddresses.count == 1)
        #expect(updated.emailAddresses[0].identifier == identifier)
        #expect(updated.emailAddresses[0].value as String == person.email)
        #expect(updated.emailAddresses[0].label == (label == "Post 165" ? CNLabelHome : label))
    }

    @Test func legacyPhoneAndAddressLabelsChangeWithoutChangingValuesOrIdentifiers() throws {
        let existing = ContactMapping.newContact(try export())
        existing.phoneNumbers = [CNLabeledValue(label: "Post 165", value: CNPhoneNumber(stringValue: "+1 (202) 555-0101"))]
        existing.postalAddresses = [existing.postalAddresses[0].settingLabel("Post 165")]
        let managed = ManagedContactFields(phoneID: existing.phoneNumbers[0].identifier, addressID: existing.postalAddresses[0].identifier)
        let plan = ContactUpdatePlan(existing: ContactMapping.project(existing), proposed: try export(), managed: managed)
        #expect(plan.changes.isEmpty)
        #expect(plan.homeLabelFields == [.phone, .address])
        #expect(plan.initialSelection.isEmpty)
        let updated = try ContactMapping.applying(plan, selected: [], to: existing)
        #expect(updated.phoneNumbers.count == 1 && updated.postalAddresses.count == 1)
        #expect(updated.phoneNumbers[0].identifier == managed.phoneID)
        #expect(updated.phoneNumbers[0].value.stringValue == "+1 (202) 555-0101")
        #expect(updated.phoneNumbers[0].label == CNLabelHome)
        #expect(updated.postalAddresses[0].identifier == managed.addressID)
        #expect(updated.postalAddresses[0].value == existing.postalAddresses[0].value)
        #expect(updated.postalAddresses[0].label == CNLabelHome)
        #expect(updated.emailAddresses == existing.emailAddresses)
        let repeated = ContactUpdatePlan(existing: ContactMapping.project(updated), proposed: try export(), managed: managed)
        #expect(repeated.changes.isEmpty)
        #expect(!repeated.hasUpdates(selected: []))
    }

    @Test func automaticLabelsPreservePersonalLabelsAndUnselectedValueDifferences() throws {
        let existing = ContactMapping.newContact(try export())
        existing.phoneNumbers = [CNLabeledValue(label: "Post 165", value: CNPhoneNumber(stringValue: "+12025550199"))]
        existing.emailAddresses = [existing.emailAddresses[0].settingLabel("Personal")]
        let managed = ManagedContactFields(phoneID: existing.phoneNumbers[0].identifier, emailID: existing.emailAddresses[0].identifier)
        let plan = ContactUpdatePlan(existing: ContactMapping.project(existing), proposed: try export(), managed: managed)
        #expect(plan.homeLabelFields.isEmpty)
        #expect(!plan.hasUpdates(selected: []))
        let updated = try ContactMapping.applying(plan, selected: [], to: existing)
        #expect(updated.phoneNumbers == existing.phoneNumbers)
        #expect(updated.emailAddresses == existing.emailAddresses)
    }

}

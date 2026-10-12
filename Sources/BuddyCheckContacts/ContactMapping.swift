import Contacts
import BuddyCheckCore

public enum ContactMapping {
    public static var keys: [any CNKeyDescriptor] { [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey,
        CNContactOrganizationNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactPostalAddressesKey].map { $0 as CNKeyDescriptor } }

    public static func postal(_ value: CNPostalAddress) -> PostalAddress {
        PostalAddress(street: value.street, city: value.city, state: value.state, postalCode: value.postalCode, country: value.isoCountryCode)
    }
    public static func postal(_ value: PostalAddress) -> CNPostalAddress {
        let address = CNMutablePostalAddress()
        address.street = value.street; address.city = value.city; address.state = value.state
        address.postalCode = value.postalCode; address.isoCountryCode = value.country
        return address
    }
    public static func project(_ contact: CNContact) -> DeviceContact {
        DeviceContact(id: contact.identifier, firstName: contact.givenName, lastName: contact.familyName, company: contact.organizationName,
            phones: contact.phoneNumbers.map { .init(id: $0.identifier, label: $0.label, value: $0.value.stringValue) },
            emails: contact.emailAddresses.map { .init(id: $0.identifier, label: $0.label, value: $0.value as String) },
            addresses: contact.postalAddresses.map { .init(id: $0.identifier, label: $0.label, value: postal($0.value)) })
    }
    public static func newContact(_ exported: ContactExport) -> CNMutableContact {
        let contact = CNMutableContact()
        contact.givenName = exported.firstName; contact.familyName = exported.lastName; contact.organizationName = exported.company
        if let phone = exported.phone { contact.phoneNumbers = [CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: phone))] }
        if let email = exported.email { contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)] }
        if let address = exported.address { contact.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: postal(address))] }
        return contact
    }
    public static func applying(_ plan: ContactUpdatePlan, selected: Set<ExportField>, to fresh: CNContact) throws -> CNMutableContact {
        try plan.validateFresh(project(fresh))
        let contact = fresh.mutableCopy() as! CNMutableContact
        for change in plan.changes where selected.contains(change.field) {
            switch change.field {
            case .firstName: contact.givenName = plan.proposed.firstName
            case .lastName: contact.familyName = plan.proposed.lastName
            case .company: contact.organizationName = plan.proposed.company
            case .phone:
                guard let value = plan.proposed.phone else { continue }
                if let index = contact.phoneNumbers.firstIndex(where: { $0.identifier == change.replacingValueID }) {
                    let old = contact.phoneNumbers[index]
                    let updated = old.settingValue(CNPhoneNumber(stringValue: value))
                    contact.phoneNumbers[index] = old.label == plan.proposed.label ? updated.settingLabel(CNLabelHome) : updated
                } else { contact.phoneNumbers.append(CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: value))) }
            case .email:
                guard let value = plan.proposed.email else { continue }
                if let index = contact.emailAddresses.firstIndex(where: { $0.identifier == change.replacingValueID }) {
                    let old = contact.emailAddresses[index]
                    let updated = old.settingValue(value as NSString)
                    contact.emailAddresses[index] = old.label == plan.proposed.label ? updated.settingLabel(CNLabelHome) : updated
                } else { contact.emailAddresses.append(CNLabeledValue(label: CNLabelHome, value: value as NSString)) }
            case .address:
                guard let value = plan.proposed.address else { continue }
                if let index = contact.postalAddresses.firstIndex(where: { $0.identifier == change.replacingValueID }) {
                    let old = contact.postalAddresses[index]
                    let updated = old.settingValue(postal(value))
                    contact.postalAddresses[index] = old.label == plan.proposed.label ? updated.settingLabel(CNLabelHome) : updated
                } else { contact.postalAddresses.append(CNLabeledValue(label: CNLabelHome, value: postal(value))) }
            }
        }
        // Standard formatting is part of Save, not another user choice. Only
        // matching entries already owned by this link qualify for migration.
        if plan.homeLabelFields.contains(.phone), let index = contact.phoneNumbers.firstIndex(where: { $0.identifier == plan.managed.phoneID }) {
            contact.phoneNumbers[index] = contact.phoneNumbers[index].settingLabel(CNLabelHome)
        }
        if plan.homeLabelFields.contains(.email), let index = contact.emailAddresses.firstIndex(where: { $0.identifier == plan.managed.emailID }) {
            contact.emailAddresses[index] = contact.emailAddresses[index].settingLabel(CNLabelHome)
        }
        if plan.homeLabelFields.contains(.address), let index = contact.postalAddresses.firstIndex(where: { $0.identifier == plan.managed.addressID }) {
            contact.postalAddresses[index] = contact.postalAddresses[index].settingLabel(CNLabelHome)
        }
        return contact
    }
}

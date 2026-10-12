import Foundation

public enum ContactIdentity: Codable, Equatable, Hashable, Sendable {
    case external(ExternalReference)
    case local(UUID)
    public init(person: Person) {
        if let reference = person.externalReference { self = .external(reference) }
        else { self = .local(person.id) }
    }
}
public struct ManagedContactFields: Codable, Equatable, Sendable {
    public var phoneID: String?
    public var emailID: String?
    public var addressID: String?
    public init(phoneID: String? = nil, emailID: String? = nil, addressID: String? = nil) {
        self.phoneID = phoneID; self.emailID = emailID; self.addressID = addressID
    }
}
public struct ContactLink: Codable, Equatable, Sendable {
    public let identity: ContactIdentity
    public var contactID: String?
    public var managed: ManagedContactFields
    public var creationPending: Bool
    public init(identity: ContactIdentity, contactID: String? = nil, managed: ManagedContactFields = .init(), creationPending: Bool = false) {
        self.identity = identity; self.contactID = contactID; self.managed = managed; self.creationPending = creationPending
    }
}
public struct ContactItem<Value: Equatable & Sendable>: Equatable, Sendable {
    public var id: String
    public var label: String?
    public var value: Value
    public init(id: String, label: String?, value: Value) { self.id = id; self.label = label; self.value = value }
}
public struct DeviceContact: Equatable, Sendable {
    public var id: String
    public var firstName: String
    public var lastName: String
    public var company: String
    public var phones: [ContactItem<String>]
    public var emails: [ContactItem<String>]
    public var addresses: [ContactItem<PostalAddress>]
    public var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
    public init(id: String, firstName: String = "", lastName: String = "", company: String = "",
                phones: [ContactItem<String>] = [], emails: [ContactItem<String>] = [], addresses: [ContactItem<PostalAddress>] = []) {
        self.id = id; self.firstName = firstName; self.lastName = lastName; self.company = company
        self.phones = phones; self.emails = emails; self.addresses = addresses
    }
}
public struct ContactExport: Equatable, Sendable {
    public let firstName: String
    public let lastName: String
    public let company: String
    public let phone: String?
    public let email: String?
    public let address: PostalAddress?
    public let label: String
    public init(person: Person, post: PostConfiguration, permitted: Bool) throws {
        guard permitted else { throw ContactsError.exportNotPermitted }
        firstName = person.firstName; lastName = person.lastName; company = post.contactsCompany
        phone = Self.nonempty(person.phone); email = Self.nonempty(person.email)
        if let value = person.address, ![value.street, value.city, value.state, value.postalCode].allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { address = value }
        else { address = nil }
        label = post.shortName
    }
    private static func nonempty(_ string: String?) -> String? {
        guard let value = string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
public enum ExportField: String, CaseIterable, Identifiable, Sendable {
    case firstName, lastName, company, phone, email, address
    public var id: Self { self }
    public var label: String {
        switch self { case .firstName: "First name"; case .lastName: "Last name"; case .company: "Company"; case .phone: "Phone"; case .email: "Email"; case .address: "Address" }
    }
}
public struct ContactChange: Identifiable, Equatable, Sendable {
    public let field: ExportField
    public let current: String
    public let proposed: String
    public let replacingValueID: String?
    public let addsValue: Bool
    public var id: ExportField { field }
    public var selectedByDefault: Bool { current.isEmpty }
    public var actionLabel: String { addsValue ? "Add Post \(field.label.lowercased())" : "Use Post \(field.label.lowercased())" }
}
public struct ContactUpdatePlan: Sendable {
    public let existing: DeviceContact
    public let proposed: ContactExport
    public let changes: [ContactChange]
    public let homeLabelFields: Set<ExportField>
    public let managed: ManagedContactFields
    public init(existing: DeviceContact, proposed: ContactExport, managed: ManagedContactFields = .init()) {
        self.existing = existing; self.proposed = proposed; self.managed = managed
        var result: [ContactChange] = []
        var homeLabels: Set<ExportField> = []
        func scalar(_ field: ExportField, _ old: String, _ new: String) {
            if !new.isEmpty && old != new { result.append(.init(field: field, current: old, proposed: new, replacingValueID: nil, addsValue: false)) }
        }
        scalar(.firstName, existing.firstName, proposed.firstName)
        scalar(.lastName, existing.lastName, proposed.lastName)
        scalar(.company, existing.company, proposed.company)
        func multi<T>(_ field: ExportField, _ old: [ContactItem<T>], _ new: T?, _ ownedID: String?, _ display: (T) -> String, _ equal: (T, T) -> Bool) where T: Equatable & Sendable {
            guard let new else { return }
            let owned = old.first { $0.id == ownedID }
            if old.contains(where: { equal($0.value, new) }) {
                if let owned, equal(owned.value, new), owned.label == proposed.label {
                    homeLabels.insert(field)
                }
                return
            }
            result.append(.init(field: field, current: owned.map { display($0.value) } ?? old.map { display($0.value) }.joined(separator: "\n"),
                                proposed: display(new), replacingValueID: owned?.id, addsValue: owned == nil))
        }
        multi(.phone, existing.phones, proposed.phone, managed.phoneID, { $0 }, phoneValuesMatch)
        multi(.email, existing.emails, proposed.email, managed.emailID, { $0 }, ==)
        multi(.address, existing.addresses, proposed.address, managed.addressID, postalText, ==)
        changes = result
        homeLabelFields = homeLabels
    }
    public func hasUpdates(selected: Set<ExportField>) -> Bool {
        !homeLabelFields.isEmpty || changes.contains { selected.contains($0.field) }
    }
    public var initialSelection: Set<ExportField> { Set(changes.filter(\.selectedByDefault).map(\.field)) }
    public func validateFresh(_ current: DeviceContact) throws {
        guard current == existing else { throw ContactsError.changedDuringReview }
    }
    // Only values explicitly used or already identical can become linked fields.
    public func linkedFields(after saved: DeviceContact, selected: Set<ExportField>) -> ManagedContactFields {
        func linked<T>(_ field: ExportField, _ values: [ContactItem<T>], _ proposedValue: T?, _ previousID: String?, _ equal: (T, T) -> Bool) -> String? where T: Equatable & Sendable {
            if selected.contains(field) || !changes.contains(where: { $0.field == field }) {
                guard let proposedValue else { return previousID }
                return values.first { equal($0.value, proposedValue) }?.id ?? previousID
            }
            return previousID
        }
        return .init(phoneID: linked(.phone, saved.phones, proposed.phone, managed.phoneID, phoneValuesMatch),
                     emailID: linked(.email, saved.emails, proposed.email, managed.emailID, ==),
                     addressID: linked(.address, saved.addresses, proposed.address, managed.addressID, ==))
    }
}
public func postalText(_ address: PostalAddress) -> String {
    [address.street, [address.city, address.state, address.postalCode].filter { !$0.isEmpty }.joined(separator: " "), address.country]
        .filter { !$0.isEmpty }.joined(separator: "\n")
}
public enum ContactsError: Error, LocalizedError, Equatable {
    case exportNotPermitted, accessRequestFailed, accessDenied, restricted, unavailable, changedDuringReview, creationUnresolved, emptyIdentifier, readOnly, saveFailed
    public var errorDescription: String? {
        switch self {
        case .exportNotPermitted: "Saving this person's Post details to Contacts is not available."
        case .accessRequestFailed: "Contacts access could not be checked. Try again."
        case .accessDenied: "Contacts access is off. Allow access in Settings to add or update a contact."
        case .restricted: "Contacts access is restricted on this device."
        case .unavailable: "This contact is unavailable. It may have been deleted or is no longer shared with this app."
        case .changedDuringReview: "The contact changed while you were reviewing it. Review the latest details before saving."
        case .creationUnresolved: "A contact may already have been saved. Choose the existing contact before creating another."
        case .emptyIdentifier: "The saved contact could not be identified. Choose it from Contacts to finish linking."
        case .readOnly: "This contact is in a read-only account and cannot be changed. Use Contact options to choose a different contact or create a new personal copy."
        case .saveFailed: "The contact could not be saved. Your previous details have been kept. Try again."
        }
    }
}

public func phoneValuesMatch(_ left: String, _ right: String) -> Bool {
    // Formatting is irrelevant; country codes and extensions must still match.
    func normalized(_ value: String) -> String {
        value.filter { !$0.isWhitespace && !"()+-.".contains($0) }
    }
    return normalized(left) == normalized(right)
}

import Contacts
import BuddyCheckCore

public enum ContactsAccess: Sendable { case notDetermined, limited, authorized, denied, restricted }

@MainActor public protocol DeviceContactsService {
    var access: ContactsAccess { get }
    func requestAccess() async throws
    func fetch(id: String) throws -> DeviceContact
    func apply(_ plan: ContactUpdatePlan, selected: Set<ExportField>) throws -> DeviceContact
}

// A narrow boundary lets failure/permission tests avoid the user's address book.
@MainActor public protocol ContactsBackend {
    var access: ContactsAccess { get }
    func requestAccess() async throws
    func fetch(id: String, keys: [any CNKeyDescriptor]) throws -> CNContact
    func save(_ contact: CNMutableContact) throws
}
@MainActor public final class SystemContactsBackend: ContactsBackend {
    public let store = CNContactStore()
    public init() {}
    public var access: ContactsAccess {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        #if os(iOS)
        case .limited: .limited
        #endif
        @unknown default: .restricted
        }
    }
    public func requestAccess() async throws { _ = try await store.requestAccess(for: .contacts) }
    public func fetch(id: String, keys: [any CNKeyDescriptor]) throws -> CNContact {
        try store.unifiedContact(withIdentifier: id, keysToFetch: keys)
    }
    public func save(_ contact: CNMutableContact) throws {
        let request = CNSaveRequest(); request.update(contact)
        try store.execute(request)
    }
}
@MainActor public final class AppleContactsService: DeviceContactsService {
    private let backend: any ContactsBackend
    public init(backend: any ContactsBackend) { self.backend = backend }
    public var access: ContactsAccess { backend.access }
    public func requestAccess() async throws {
        if access == .notDetermined {
            do { try await backend.requestAccess() }
            catch {
                if access == .denied { throw ContactsError.accessDenied }
                if access == .restricted { throw ContactsError.restricted }
                throw ContactsError.accessRequestFailed
            }
        }
        try requireAccess()
    }
    public func requireAccess() throws {
        switch access {
        case .authorized, .limited: return
        case .restricted: throw ContactsError.restricted
        case .denied, .notDetermined: throw ContactsError.accessDenied
        }
    }
    public func nativeContact(id: String, keys: [any CNKeyDescriptor] = ContactMapping.keys) throws -> CNContact {
        try requireAccess()
        do { return try backend.fetch(id: id, keys: keys) }
        catch { throw ContactsError.unavailable }
    }
    public func fetch(id: String) throws -> DeviceContact { ContactMapping.project(try nativeContact(id: id)) }
    public func apply(_ plan: ContactUpdatePlan, selected: Set<ExportField>) throws -> DeviceContact {
        let fresh = try nativeContact(id: plan.existing.id)
        let updated = try ContactMapping.applying(plan, selected: selected, to: fresh)
        if plan.hasUpdates(selected: selected) {
            do { try requireAccess(); try backend.save(updated) }
            catch let error as ContactsError { throw error }
            catch {
                let nativeError = error as NSError
                if nativeError.domain == CNErrorDomain,
                   [CNError.Code.recordNotWritable.rawValue, CNError.Code.parentContainerNotWritable.rawValue].contains(nativeError.code) {
                    throw ContactsError.readOnly
                }
                throw ContactsError.saveFailed
            }
        }
        return ContactMapping.project(updated)
    }
}

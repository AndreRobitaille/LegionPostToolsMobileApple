import SwiftUI
import Contacts
import ContactsUI
import BuddyCheckCore
import BuddyCheckContacts
import BuddyCheckAPI

struct ConnectedContactsScreen: View {
    let account: ConnectedAccount
    let personID: Int
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @State private var backend = SystemContactsBackend()
    @State private var projection: ContactExportResponse?
    @State private var review: ContactUpdatePlan?
    @State private var reviewCancelled = false
    @State private var selected: Set<ExportField> = []
    @State private var editor: ContactEditorPresentation?
    @State private var showPicker = false
    @State private var showAccessPicker = false
    @State private var confirmAnother = false
    @State private var createAfterConfirmation = false
    @State private var busy = false
    @State private var error: String?
    @State private var reviewError: String?
    @State private var reviewFailure: (contactID: String, message: String)?
    @State private var notice: String?
    @State private var access = ContactsAccess.notDetermined
    @State private var linkedContactAvailable = false
    private var service: AppleContactsService {
        #if DEBUG && targetEnvironment(simulator)
        AppleContactsService(backend: SyntheticConnectedFixture.contactsBackend(backend))
        #else
        AppleContactsService(backend: backend)
        #endif
    }
    private var link: ConnectedContactLink { account.journal?.snapshot.contactLinks?[personID] ?? .init() }
    var body: some View {
        Page(scrollResetID: notice.map { "notice.\($0)" } ?? review.map { "review.\($0.existing.id)" }) {
            if let projection {
                PersonCard(name: [projection.fields.firstName, projection.fields.lastName].joined(separator: " "))
            }
            if let notice { WorkingSurface { Text(notice).font(.headline) } }
            if let review {
                SectionTitle("Post contact details")
                if review.changes.isEmpty {
                    Text(review.homeLabelFields.isEmpty ? "This contact is up to date." : "Save to finish updating this contact.")
                    postDetails
                } else {
                    Text("Choose the Post details to use. Other personal details stay as they are.")
                }
                ForEach(review.changes) { change in
                    WorkingSurface {
                        Text(change.field.label).font(.headline)
                        if !change.current.isEmpty { Text("Current: \(change.current)") }
                        Text("Post: \(change.proposed)")
                        Toggle(change.actionLabel, isOn: Binding(get: { selected.contains(change.field) }, set: { on in
                            if on { selected.insert(change.field) } else { selected.remove(change.field) }
                        }))
                    }
                }
                if review.hasUpdates(selected: selected) {
                    Button("Save changes") { Task { await apply(review) } }.buttonStyle(ActionStyle()).disabled(busy)
                } else if link.contactID != review.existing.id || link.creationPending {
                    Button("Use this contact") { Task { await apply(review) } }.buttonStyle(ActionStyle()).disabled(busy)
                }
                if link.contactID == review.existing.id && review.changes.isEmpty && review.homeLabelFields.isEmpty {
                    Button("Open contact") { Task { await openContact(review.existing.id) } }.buttonStyle(ActionStyle()).disabled(busy)
                }
                if link.contactID != review.existing.id || link.creationPending {
                    Button("Cancel review") { self.review = nil; selected = [] }.buttonStyle(ActionStyle(primary: false)).disabled(busy)
                }
            } else if projection != nil {
                postDetails
                if link.creationPending {
                    Text("A contact may already have been saved. Choose it below to finish linking.")
                }
                if let id = link.contactID {
                    if linkedContactAvailable {
                        Button("Review Post updates") { Task { await prepareReview(id) } }.buttonStyle(ActionStyle()).disabled(busy)
                    } else { Text("The linked contact is unavailable. It may have been deleted or is no longer shared with this app.") }
                }
                if !linkedContactAvailable || link.creationPending {
                    Button("Create new contact") { startCreation() }.buttonStyle(ActionStyle()).disabled(busy)
                    Button("Choose existing contact") { chooseExisting() }.buttonStyle(ActionStyle(primary: false)).disabled(busy)
                }
                Text("This creates a personal Contacts copy. Later Post changes require another review; signing out does not remove the copy.").font(.footnote)
            }
            if access == .denied {
                Button("Open Contacts settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }.buttonStyle(ActionStyle())
            }
            if access == .limited && !linkedContactAvailable {
                Button("Choose contacts shared with this app") { showAccessPicker = true }.buttonStyle(ActionStyle(primary: false))
            }
            if let reviewFailure { Text(reviewFailure.message) }
            else if let error { Text(error) }
            if busy { ProgressView("Checking Contacts") }
            if !busy && projection == nil { Button("Retry Post details") { Task { await load() } }.buttonStyle(ActionStyle()) }
        }.id(projection?.version).navigationTitle("Phone contact")
            .toolbar {
                if projection != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if review != nil {
                                Button("Cancel review") { review = nil; selected = []; reviewCancelled = true }
                            }
                            if let id = link.contactID, linkedContactAvailable {
                                Button("Open contact") { Task { await openContact(id) } }
                                Button("Choose existing contact") { chooseExisting() }
                                Button("Create new contact") { startCreation() }
                                if access == .limited {
                                    Button("Choose contacts shared with this app") { showAccessPicker = true }
                                }
                            }
                            Button("Refresh Post details") { Task { await load() } }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Contact options").disabled(busy)
                    }
                }
            }
            .alert("Contacts", isPresented: Binding(get: { reviewError != nil }, set: { if !$0 { reviewError = nil } })) {
                Button(review == nil ? "OK" : "Return to review") { reviewError = nil }
            } message: { Text(reviewError ?? "Please try again.") }
            .task { await load() }
            .onChange(of: phase) { _, phase in if phase == .active { refreshContacts() } }
            .onReceive(NotificationCenter.default.publisher(for: .CNContactStoreDidChange).receive(on: RunLoop.main)) { _ in refreshContacts() }
            .onChange(of: showAccessPicker) { _, shown in if !shown { refreshContacts() } }
            .sheet(isPresented: $showPicker, onDismiss: { refreshContacts() }) { NativeContactPicker { id in showPicker = false; if let id { Task { await prepareReview(id) } } } }
            .fullScreenCover(item: $editor, onDismiss: { refreshContacts() }) { presentation in
                NativeContactEditor(presentation: presentation, store: backend.store) { result in
                    editor = nil
                    guard presentation.creating else { refreshContacts(); return }
                    do {
                        var updated = link; updated.creationPending = presentation.hasEarlierPendingCreation
                        if let result { updated = .init(contactID: result.identifier) }
                        try remember(updated)
                        // Keep the saved ID even if access changes before this read.
                        // Own only values the caller retained from the creation form.
                        if let result, let proposed = presentation.proposed,
                           let saved = try? service.fetch(id: result.identifier) {
                            let plan = ContactUpdatePlan(existing: saved, proposed: proposed)
                            let managed = plan.linkedFields(after: saved, selected: [])
                            do {
                                try remember(.init(contactID: saved.id, phoneID: managed.phoneID,
                                                   emailID: managed.emailID, addressID: managed.addressID))
                            } catch {
                                self.error = "The contact was saved, but its field links could not be saved. Review the existing card before another update."
                            }
                        }
                        notice = result == nil ? "Contact creation cancelled." : "Contact saved."
                    } catch { self.error = "Contacts may have saved the card, but its link could not be saved. Choose the existing contact before creating another." }
                }.interactiveDismissDisabled()
            }
            .contactAccessPicker(isPresented: $showAccessPicker) { @Sendable _ in Task { @MainActor in refreshContacts() } }
            .sheet(isPresented: $confirmAnother, onDismiss: {
                if createAfterConfirmation {
                    createAfterConfirmation = false
                    Task { await create() }
                }
            }) {
                ContactCreationConfirmation {
                    createAfterConfirmation = true; confirmAnother = false
                }
            }
    }
    @ViewBuilder private var postDetails: some View {
        if let projection, let permitted = try? PermittedContactCopy(projection) {
            WorkingSurface {
                Text(permitted.company).font(.headline)
                if let phone = permitted.phone { Text(phone) }
                if let email = permitted.email { Text(email) }
                if let address = permitted.address { Text([address.street, address.city, address.state, address.postalCode].compactMap { $0 }.joined(separator: "\n")) }
            }
        }
    }
    private func chooseExisting() {
        Task { await perform {
            try await service.requestAccess(); access = service.access
            _ = try await freshProjection(); showPicker = true
        } }
    }
    private func startCreation() {
        if link.contactID != nil || link.creationPending { confirmAnother = true }
        else { Task { await create() } }
    }
    private func openContact(_ id: String) async {
        await perform {
            _ = try await freshProjection()
            let contact = try service.nativeContact(id: id, keys: [CNContactViewController.descriptorForRequiredKeys()])
            editor = ContactEditorPresentation(contact: contact, creating: false)
        }
    }
    private func freshProjection() async throws -> ContactExportResponse {
        do {
            let fresh = try await account.perform { client, token in try await client.contactExport(personID: personID, token: token) }
            // Validate even the identity fields before the projection is displayed.
            _ = try PermittedContactCopy(fresh)
            return fresh
        } catch {
            clearProjection()
            throw error
        }
    }
    private func clearProjection() {
        projection = nil; review = nil; selected = []; notice = nil; reviewFailure = nil
    }
    private func export(_ value: ContactExportResponse) throws -> ContactExport {
        let allowed = try PermittedContactCopy(value)
        let address = allowed.address.map { PostalAddress(street: $0.street ?? "", city: $0.city ?? "", state: $0.state ?? "", postalCode: $0.postalCode ?? "", country: $0.country ?? "") }
        let person = Person(id: UUID(), firstName: allowed.firstName, lastName: allowed.lastName, phone: allowed.phone, email: allowed.email, address: address, isSynthetic: false)
        let post = PostConfiguration(shortName: account.session?.installation.name ?? "Post", fullName: "", location: "", contactsCompany: allowed.company)
        return try ContactExport(person: person, post: post, permitted: true)
    }
    private func remember(_ value: ConnectedContactLink) throws {
        guard let journal = account.journal else { throw ClientError.journalUnavailable }
        try journal.rememberContact(personID: personID, link: value)
    }
    private func refreshContacts() {
        access = service.access
        // Recheck once native presentations or an in-flight operation finish.
        guard editor == nil && !showPicker && !showAccessPicker && !busy else { return }
        linkedContactAvailable = link.contactID.flatMap { try? service.fetch(id: $0) } != nil
        if let failure = reviewFailure, (try? service.fetch(id: failure.contactID)) != nil { reviewFailure = nil }
        if let plan = review {
            do { try plan.validateFresh(service.fetch(id: plan.existing.id)) }
            catch {
                review = nil; selected = []; notice = nil
                reviewFailure = (plan.existing.id, (error as? ContactsError)?.errorDescription ?? safeMessage(error))
            }
        }
        if review == nil, !reviewCancelled, reviewFailure == nil, error == nil, linkedContactAvailable, !link.creationPending,
           let id = link.contactID, let projection,
           let existing = try? service.fetch(id: id), let proposed = try? export(projection) {
            let managed = ManagedContactFields(phoneID: link.phoneID, emailID: link.emailID, addressID: link.addressID)
            let plan = ContactUpdatePlan(existing: existing, proposed: proposed, managed: managed)
            review = plan; selected = plan.initialSelection
        }
    }
    private func load() async {
        await perform {
            reviewCancelled = false
            clearProjection()
            access = service.access; projection = try await freshProjection()
        }
    }
    private func create() async {
        await perform {
            try await service.requestAccess(); access = service.access
            let fresh = try await freshProjection(); let proposed = try export(fresh)
            let hasEarlierPendingCreation = link.creationPending
            var pending = link; pending.creationPending = true
            try remember(pending)
            projection = fresh; notice = nil
            editor = ContactEditorPresentation(contact: ContactMapping.newContact(proposed), creating: true, proposed: proposed,
                                               hasEarlierPendingCreation: hasEarlierPendingCreation)
        }
    }
    private func prepareReview(_ id: String) async {
        await perform {
            reviewCancelled = false
            try await service.requestAccess(); access = service.access
            let fresh = try await freshProjection()
            let existing = try service.fetch(id: id)
            let managed = link.contactID == id ? ManagedContactFields(phoneID: link.phoneID, emailID: link.emailID, addressID: link.addressID) : .init()
            let plan = ContactUpdatePlan(existing: existing, proposed: try export(fresh), managed: managed)
            projection = fresh; review = plan; selected = plan.initialSelection; notice = nil
        }
    }
    private func apply(_ plan: ContactUpdatePlan) async {
        await perform(presentReviewError: true) {
            let fresh = try await freshProjection()
            guard fresh.version == projection?.version, try export(fresh) == plan.proposed else {
                review = nil; selected = []; projection = fresh
                throw ContactsError.changedDuringReview
            }
            try plan.validateFresh(service.fetch(id: plan.existing.id))
            try remember(.init(contactID: plan.existing.id, phoneID: plan.managed.phoneID, emailID: plan.managed.emailID, addressID: plan.managed.addressID))
            let saved = try service.apply(plan, selected: selected)
            let managed = plan.linkedFields(after: saved, selected: selected)
            do { try remember(.init(contactID: saved.id, phoneID: managed.phoneID, emailID: managed.emailID, addressID: managed.addressID)) }
            catch { self.error = "The contact was updated, but its field links could not be saved. Review the existing card before another update." }
            notice = plan.hasUpdates(selected: selected) ? "Contact updated." : "Contact linked."
            review = nil; selected = []; reviewCancelled = false
        }
    }
    private func perform(presentReviewError: Bool = false, _ action: () async throws -> Void) async {
        guard !busy else { return }; busy = true; error = nil; reviewFailure = nil
        defer {
            busy = false; refreshContacts()
            if presentReviewError, let error { reviewError = error; self.error = nil }
        }
        do { try await action() }
        catch ClientError.connectionUnavailable { self.error = "The Post could not be reached. Retry to load current contact details." }
        catch ClientError.invalidResponse { self.error = "These Post details could not be verified. Retry before copying them." }
        catch { self.error = (error as? ContactsError)?.errorDescription ?? safeMessage(error) }
    }
}

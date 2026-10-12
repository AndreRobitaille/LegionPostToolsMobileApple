import SwiftUI
import Contacts
import ContactsUI
import BuddyCheckCore
import BuddyCheckContacts

struct ContactsScreen: View {
    let person: Person
    let post: PostConfiguration
    let store: CheckStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @State private var backend = SystemContactsBackend()
    private var service: AppleContactsService { AppleContactsService(backend: backend) }
    @State private var access = ContactsAccess.notDetermined
    @State private var linkedContact: DeviceContact?
    @State private var unavailable = false
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
    @State private var notice: String?
    private var link: ContactLink? { store.contactLink(for: person) }

    var body: some View {
        Page(scrollResetID: notice.map { "notice.\($0)" } ?? review?.existing.id) {
            PersonCard(person: person)
            if let notice { WorkingSurface { Label(notice, systemImage: "checkmark.circle").font(.headline) } }
            if access == .denied || access == .restricted {
                WorkingSurface {
                    SectionTitle(access == .denied ? "Contacts access is off" : "Contacts access is restricted")
                    Text(access == .denied ? "Allow Contacts access in Settings to add or update a contact." : "This device does not allow Contacts access for the app.")
                }
                if access == .denied {
                    Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }.buttonStyle(ActionStyle())
                }
                Button("Check access again") { refresh() }.buttonStyle(ActionStyle(primary: false))
            } else if let review { reviewForm(review) }
            else { contactActions }
        // Reset the scroll position without replacing navigation appearance.
        }.navigationTitle("Phone contact")
            .toolbar {
                if link?.contactID != nil && !unavailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if review != nil {
                                Button("Cancel review") { review = nil; selected = []; reviewCancelled = true }
                            }
                            if let id = link?.contactID { Button("Open contact") { openContact(id: id) } }
                            Button("Choose existing contact") { authorized { showPicker = true } }
                            Button("Create another contact") { confirmAnother = true }
                            if access == .limited {
                                Button("Choose contacts this app can access") { showAccessPicker = true }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Contact options").disabled(busy)
                    }
                }
            }
            .task { refresh() }
            .onChange(of: phase) { _, value in if value == .active { refresh() } }
            .onReceive(NotificationCenter.default.publisher(for: .CNContactStoreDidChange).receive(on: RunLoop.main)) { _ in
                if editor == nil && !showPicker { refresh() }
            }
            .sheet(isPresented: $showPicker) {
                NativeContactPicker { id in
                    showPicker = false
                    if let id { prepareReview(id: id) }
                }
            }
            .fullScreenCover(item: $editor, onDismiss: { refresh() }) { presentation in
                NativeContactEditor(presentation: presentation, store: backend.store) { result in
                    editor = nil
                    finishEditor(result, creating: presentation.creating, preservePending: presentation.hasEarlierPendingCreation)
                }.interactiveDismissDisabled(presentation.creating)
            }
            .contactAccessPicker(isPresented: $showAccessPicker) { @Sendable _ in
                // ContactsUI can deliver its XPC reply off the main executor.
                Task { @MainActor in refresh() }
            }
            .alert("Contacts", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "Please try again.") }
            .sheet(isPresented: $confirmAnother, onDismiss: {
                if createAfterConfirmation {
                    createAfterConfirmation = false
                    create(explicitAnother: true)
                }
            }) {
                ContactCreationConfirmation {
                    createAfterConfirmation = true; confirmAnother = false
                }
            }
    }
    @ViewBuilder private var contactActions: some View {
        if link?.creationPending == true {
            WorkingSurface {
                SectionTitle("Finish linking your contact")
                Text("A contact may already have been saved. Choose it from Contacts to finish linking it here.")
            }
            chooseExistingButton
            Button("Create another contact") { confirmAnother = true }.buttonStyle(ActionStyle(primary: false))
        } else if let linkedContact {
            WorkingSurface {
                SectionTitle("Linked in Contacts")
                Text(linkedContact.name.isEmpty ? "Unnamed contact" : linkedContact.name).font(.title3)
                if !linkedContact.company.isEmpty { Text(linkedContact.company) }
            }
            Button("Review Post updates") { prepareReview(id: linkedContact.id) }.buttonStyle(ActionStyle())
            Button("Open contact") { openContact(id: linkedContact.id) }.buttonStyle(ActionStyle(primary: false))
        } else if unavailable {
            WorkingSurface {
                SectionTitle("Contact unavailable")
                Text("It may have been deleted or is no longer shared with this app. Your saved link has been kept.")
            }
            chooseExistingButton
            Button("Create another contact") { confirmAnother = true }.buttonStyle(ActionStyle(primary: false))
        } else {
            WorkingSurface {
                SectionTitle("Add to Contacts")
                contactField("Company", post.contactsCompany)
                if let phone = person.phone { contactField("Phone number", phone) }
                if let email = person.email { contactField("Email address", email) }
                if let address = person.address { contactField("Mailing address", postalText(address)) }
            }
            Button("Create new contact") { create(explicitAnother: false) }.buttonStyle(ActionStyle()).disabled(busy)
            chooseExistingButton
        }
        if access == .limited && (link?.contactID == nil || unavailable) {
            Button("Choose contacts this app can access") { showAccessPicker = true }.buttonStyle(ActionStyle(primary: false))
        }
        Text("This saves a personal copy in Contacts. It may sync with your Contacts account and stays there if you remove this app. Updates happen only when you choose them.").font(.footnote)
    }
    private func contactField(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            Text(value)
        }.accessibilityElement(children: .combine)
    }
    private var chooseExistingButton: some View {
        Button("Choose existing contact") { authorized { showPicker = true } }.buttonStyle(ActionStyle(primary: false)).disabled(busy)
    }
    private func reviewForm(_ plan: ContactUpdatePlan) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionTitle("Post contact details")
            if plan.changes.isEmpty {
                WorkingSurface {
                    Text(plan.homeLabelFields.isEmpty ? "This contact is up to date." : "Save to finish updating this contact.")
                    contactField("Company", plan.existing.company)
                    if let phone = person.phone { contactField("Phone number", phone) }
                    if let email = person.email { contactField("Email address", email) }
                    if let address = person.address { contactField("Mailing address", postalText(address)) }
                }
            } else {
                Text("Choose the Post details to use. Other personal details stay as they are.")
                ForEach(plan.changes) { change in
                    WorkingSurface {
                        SectionTitle(change.field.label)
                        Text("On your phone").font(.subheadline.bold())
                        Text(change.current.isEmpty ? "Not set" : change.current)
                        Text("From \(post.shortName)").font(.subheadline.bold())
                        Text(change.proposed)
                        if change.addsValue && !change.current.isEmpty { Text("Existing entries will stay.").font(.footnote) }
                        Button {
                            if selected.contains(change.field) { selected.remove(change.field) } else { selected.insert(change.field) }
                        } label: {
                            Label(change.actionLabel, systemImage: selected.contains(change.field) ? "checkmark.circle.fill" : "circle")
                        }.buttonStyle(ActionStyle(primary: selected.contains(change.field)))
                            .accessibilityAddTraits(selected.contains(change.field) ? .isSelected : [])
                    }
                }
            }
            if plan.hasUpdates(selected: selected) {
                Button("Save changes") { apply(plan) }.buttonStyle(ActionStyle()).disabled(busy)
            } else if link?.contactID != plan.existing.id || link?.creationPending == true {
                Button("Use this contact") { apply(plan) }.buttonStyle(ActionStyle()).disabled(busy)
            }
            if link?.contactID == plan.existing.id && plan.changes.isEmpty && plan.homeLabelFields.isEmpty {
                Button("Open contact") { openContact(id: plan.existing.id) }.buttonStyle(ActionStyle()).disabled(busy)
            }
            if link?.contactID != plan.existing.id || link?.creationPending == true {
                Button("Cancel review") { review = nil; selected = []; refresh() }.buttonStyle(ActionStyle(primary: false))
            }
        }
    }
    private func export() throws -> ContactExport {
        // Connected export must supply a reviewed server permission, not just roster visibility.
        try ContactExport(person: person, post: post, permitted: person.isSynthetic)
    }
    private func authorized(_ action: @escaping @MainActor () throws -> Void) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do { try await service.requestAccess(); access = service.access; try action() }
            catch { access = service.access; report(error) }
        }
    }
    private func report(_ problem: Error) {
        error = (problem as? ContactsError)?.errorDescription ?? (problem as? WorkflowError)?.errorDescription
            ?? "The contact link couldn't be saved in this app. Try again before creating another contact."
    }
    private func refresh() {
        access = service.access
        guard editor == nil && !showPicker else { return }
        guard access == .authorized || access == .limited else { linkedContact = nil; review = nil; return }
        if let plan = review {
            do { try plan.validateFresh(service.fetch(id: plan.existing.id)) }
            catch { review = nil; selected = []; report(error) }
        }
        guard let id = link?.contactID else { linkedContact = nil; unavailable = false; return }
        do {
            linkedContact = try service.fetch(id: id); unavailable = false
            if review == nil, !reviewCancelled, link?.creationPending != true, let linkedContact {
                let plan = ContactUpdatePlan(existing: linkedContact, proposed: try export(), managed: link?.managed ?? .init())
                review = plan; selected = plan.initialSelection
            }
        }
        catch { linkedContact = nil; unavailable = true }
    }
    private func create(explicitAnother: Bool) {
        authorized {
            let contact = ContactMapping.newContact(try export())
            let hasEarlierPendingCreation = link?.creationPending == true
            try store.beginContactCreation(person: person, explicitlyCreateAnother: explicitAnother)
            notice = nil
            editor = ContactEditorPresentation(contact: contact, creating: true, hasEarlierPendingCreation: hasEarlierPendingCreation)
        }
    }
    private func finishEditor(_ result: CNContact?, creating: Bool, preservePending: Bool) {
        if creating {
            guard let result else {
                do { if !preservePending { try store.cancelContactCreation(person: person) } }
                catch { report(error) }
                refresh(); return
            }
            do {
                // Remember the saved identifier even if permission changes before a re-fetch.
                try store.rememberContact(person: person, contactID: result.identifier, managed: .init())
                if let fetched = try? service.fetch(id: result.identifier), let proposed = try? export() {
                    let plan = ContactUpdatePlan(existing: fetched, proposed: proposed)
                    try store.rememberContact(person: person, contactID: fetched.id, managed: plan.linkedFields(after: fetched, selected: []))
                }
                notice = "Contact saved."
            } catch {
                self.error = "The contact was saved in Contacts, but this app couldn't finish remembering the link. Choose the existing contact to finish."
            }
        }
        refresh()
    }
    private func prepareReview(id: String) {
        notice = nil; reviewCancelled = false
        do {
            let fetched = try service.fetch(id: id)
            let managed = link?.contactID == fetched.id ? link!.managed : ManagedContactFields()
            let plan = ContactUpdatePlan(existing: fetched, proposed: try export(), managed: managed)
            review = plan; selected = plan.initialSelection
        } catch { report(error); refresh() }
    }
    private func apply(_ plan: ContactUpdatePlan) {
        guard !busy else { return }; busy = true
        defer { busy = false }
        do {
            // Persist the explicit association before an external update. A failed update
            // leaves a usable link and never implies that the proposed fields were saved.
            try plan.validateFresh(service.fetch(id: plan.existing.id))
            try store.rememberContact(person: person, contactID: plan.existing.id, managed: plan.managed)
            let saved = try service.apply(plan, selected: selected)
            do {
                try store.rememberContact(person: person, contactID: saved.id, managed: plan.linkedFields(after: saved, selected: selected))
            } catch {
                self.error = "The contact was updated, but this app couldn't remember every linked field. Review it again before another update."
            }
            notice = plan.hasUpdates(selected: selected) ? "Contact updated." : "Contact linked."
            review = nil; selected = []; reviewCancelled = false; refresh()
        } catch { report(error) }
    }
    private func openContact(id: String) {
        authorized {
            let contact = try service.nativeContact(id: id, keys: [CNContactViewController.descriptorForRequiredKeys()])
            editor = ContactEditorPresentation(contact: contact, creating: false)
        }
    }
}

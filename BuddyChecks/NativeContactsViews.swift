import SwiftUI
import Contacts
import ContactsUI
import BuddyCheckCore

struct ContactEditorPresentation: Identifiable {
    let id = UUID()
    let contact: CNContact
    let creating: Bool
    let proposed: ContactExport?
    // Cancelling this editor cannot settle whether an earlier attempt saved a card.
    let hasEarlierPendingCreation: Bool
    init(contact: CNContact, creating: Bool, proposed: ContactExport? = nil, hasEarlierPendingCreation: Bool = false) {
        self.contact = contact; self.creating = creating; self.proposed = proposed
        self.hasEarlierPendingCreation = hasEarlierPendingCreation
    }
}
struct NativeContactEditor: UIViewControllerRepresentable {
    let presentation: ContactEditorPresentation
    let store: CNContactStore
    let completion: (CNContact?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = presentation.creating ? CNContactViewController(forNewContact: presentation.contact) : CNContactViewController(for: presentation.contact)
        controller.contactStore = store
        controller.delegate = context.coordinator
        controller.allowsEditing = true
        // Even existing personal cards cannot launch calls/messages from this synthetic app.
        controller.allowsActions = false
        if !presentation.creating {
            controller.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: context.coordinator, action: #selector(Coordinator.close))
        }
        return UINavigationController(rootViewController: controller)
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    @MainActor final class Coordinator: NSObject, @preconcurrency CNContactViewControllerDelegate {
        let completion: (CNContact?) -> Void
        init(completion: @escaping (CNContact?) -> Void) { self.completion = completion }
        @objc func close() { completion(nil) }
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            #if DEBUG && targetEnvironment(simulator)
            if let contact {
                do {
                    if try SyntheticConnectedFixture.holdSavedContactBeforeLink(contact) {
                        viewController.navigationItem.title = "Saved before link test hold"
                        return
                    }
                } catch { preconditionFailure("Synthetic native-save interruption guard failed") }
            }
            #endif
            completion(contact)
        }
        func contactViewController(_ viewController: CNContactViewController, shouldPerformDefaultActionFor property: CNContactProperty) -> Bool { false }
    }
}
struct NativeContactPicker: UIViewControllerRepresentable {
    let selected: (String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForSelectionOfContact = NSPredicate(value: true)
        return picker
    }
    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, @preconcurrency CNContactPickerDelegate {
        let selected: (String?) -> Void
        init(selected: @escaping (String?) -> Void) { self.selected = selected }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { selected(nil) }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) { selected(contact.identifier) }
    }
}

/// Scrollable confirmation preserves the full explanation at accessibility sizes.
struct ContactCreationConfirmation: View {
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Page {
                SectionTitle("Create another contact?")
                Text("A contact may already exist.").fixedSize(horizontal: false, vertical: true)
                Text("Choose it from Contacts to avoid a duplicate.").fixedSize(horizontal: false, vertical: true)
                Button("Cancel") { dismiss() }.buttonStyle(ActionStyle(primary: false))
                Button("Create another contact") { confirm() }.buttonStyle(ActionStyle())
            }.navigationTitle("New contact")
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

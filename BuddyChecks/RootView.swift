import SwiftUI
import BuddyCheckCore

private enum MainTab: Hashable { case home, followUps }
private enum Route: Hashable {
    case suggestions, people(manual: Bool), person(UUID), draft, check(UUID), history, followUp(UUID), reschedule(UUID), contacts(UUID)
}
private enum NewWork { case people(Bool), start(UUID, DraftOrigin), correction(UUID) }

struct RootView: View {
    let store: CheckStore
    let reminders: DeviceReminders
    let reminderNamespace: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var reminderNotice: String?
    private let post = PostConfiguration.synthetic
    @State private var tab = MainTab.home
    @State private var homePath: [Route] = []
    @State private var followUpPath: [Route] = []
    @State private var search = ""
    @State private var suggestions = SuggestionSession(source: SyntheticSuggestionSource())
    @State private var error: String?
    @State private var pendingWork: NewWork?
    @State private var showUnfinished = false
    @State private var showDiscard = false
    @State private var cancelFollowUpID: UUID?
    @State private var editingDate = Date()
    @State private var showLocalReminder = false
    private var path: [Route] {
        get { tab == .home ? homePath : followUpPath }
        nonmutating set { if tab == .home { homePath = newValue } else { followUpPath = newValue } }
    }
    private var openFollowUps: [FollowUp] { store.followUps.filter { $0.status == .open } }

    var body: some View {
        PostConnectionRoot(showLocalReminder: $showLocalReminder) { openSettings, returnToPost in
            if let loadError = store.loadError {
                NavigationStack {
                    Page {
                        SectionTitle("Saved work unavailable")
                        Text(loadError)
                        Button("Retry") { store.reload() }.buttonStyle(ActionStyle())
                    }.navigationTitle("Buddy Checks")
                }
            } else {
                TabView(selection: $tab) {
                    NavigationStack(path: $homePath) {
                        home(openSettings: openSettings).navigationDestination(for: Route.self, destination: destination)
                            .toolbar { if let returnToPost { ToolbarItem(placement: .topBarLeading) { Button("Back to Post", action: returnToPost) } } }
                    }.tabItem { Label("Home", systemImage: "house") }.tag(MainTab.home)
                    NavigationStack(path: $followUpPath) {
                        followUpList.navigationDestination(for: Route.self, destination: destination)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) { Button("Account and Post settings", systemImage: "person.crop.circle", action: openSettings) }
                                if let returnToPost { ToolbarItem(placement: .topBarLeading) { Button("Back to Post", action: returnToPost) } }
                            }
                    }.tabItem { Label("Follow-ups", systemImage: "calendar") }.tag(MainTab.followUps)
                }
            }
        }
        .task { await SystemReminderScheduler.removeOrphanedConnectedAlerts(); await reminders.refresh(); openReminder() }
        .onChange(of: store.snapshot) { _, _ in Task { await reminders.refresh() } }
        .onChange(of: scenePhase) { _, value in
            if value == .active { Task { await SystemReminderScheduler.removeOrphanedConnectedAlerts(); await reminders.refresh(); openReminder() } }
        }
        .onChange(of: ReminderInbox.shared.link) { _, _ in openReminder() }
        .onChange(of: ReminderInbox.shared.deliveryRevision) { _, _ in Task { await reminders.refresh() } }
        .alert("Follow-up reminder", isPresented: Binding(get: { reminderNotice != nil }, set: { if !$0 { reminderNotice = nil } })) {
            Button("OK", role: .cancel) { reminderNotice = nil }
        } message: { Text(reminderNotice ?? "") }
        .alert("Couldn't finish that action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "Please try again.") }
        .confirmationDialog("You have an unfinished check", isPresented: $showUnfinished, titleVisibility: .visible) {
            Button("Continue unfinished check") { pendingWork = nil; path = [.draft] }
            Button("Discard and start another", role: .destructive) {
                perform {
                    if let draft = store.draft { try store.discardDraft(id: draft.id) }
                    if let work = pendingWork { try begin(work) }
                    pendingWork = nil
                }
            }
            Button("Keep unfinished check", role: .cancel) { pendingWork = nil }
        }
        .confirmationDialog("Discard this unfinished check?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard check", role: .destructive) {
                perform { if let draft = store.draft { try store.discardDraft(id: draft.id) }; path = [] }
            }
        } message: { Text("Previously saved checks will stay unchanged.") }
        .confirmationDialog("Cancel this follow-up?", isPresented: Binding(get: { cancelFollowUpID != nil }, set: { if !$0 { cancelFollowUpID = nil } }), titleVisibility: .visible) {
            Button("Cancel follow-up", role: .destructive) {
                if let id = cancelFollowUpID { perform { try store.closeFollowUp(id: id, status: .cancelled) } }
                cancelFollowUpID = nil
            }
        }
    }

    private func openReminder() {
        guard let link = ReminderInbox.shared.link else { return }
        if link.namespace.hasPrefix("connected.") { showLocalReminder = false; return }
        ReminderInbox.shared.link = nil
        guard link.namespace == reminderNamespace else {
            reminderNotice = "This reminder belongs to a different set of saved work. No follow-up was changed."
            return
        }
        switch reminders.resolve(link.reminder) {
        case .storageUnavailable: reminderNotice = "Saved work is unavailable. Retry opening it before using this reminder."
        case .missing: reminderNotice = "This follow-up is no longer available."
        case .followUp(let id, let changed):
            showLocalReminder = true; tab = .followUps; followUpPath = [.followUp(id)]
            if changed { reminderNotice = "This follow-up has changed since the reminder was scheduled. Its current details are shown."
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { self.error = (error as? WorkflowError)?.errorDescription ?? "The change couldn't be saved on this iPhone. Your previous work is still available. Try again." }
    }
    private func request(_ work: NewWork) {
        if store.draft != nil { pendingWork = work; showUnfinished = true }
        else { perform { try begin(work) } }
    }
    private func begin(_ work: NewWork) throws {
        switch work {
        case .people(let manual): search = ""; path.append(.people(manual: manual))
        case .start(let id, let origin):
            try store.begin(personID: id, origin: origin, timeZone: TimeZone.current.identifier)
            path.append(.draft)
        case .correction(let id): try store.beginCorrection(checkID: id); path.append(.draft)
        }
    }
    private func save(_ id: UUID, followUp: Bool) {
        perform { let saved = try store.saveDraft(id: id, includeFollowUp: followUp); path = [.check(saved.id)] }
    }
    private func goHome() { tab = .home; homePath = [] }

    private func home(openSettings: @escaping () -> Void) -> some View {
        Page {
            VStack(alignment: .leading, spacing: 6) {
                Text(post.shortName).font(.largeTitle.bold()).foregroundStyle(Palette.navy)
                Text("\(post.fullName) · \(post.location)").font(.subheadline)
            }
            if let draft = store.draft, let person = store.person(draft.personID) {
                WorkingSurface {
                    Label("Unfinished check", systemImage: "pencil").font(.subheadline)
                    Text(person.name).font(.title2.bold())
                    Button("Continue with \(person.firstName)") { path = [.draft] }.buttonStyle(ActionStyle())
                }
            }
            VStack(spacing: 12) {
                // Browsing a person or their Contacts card must not discard an unfinished check.
                Button { search = ""; path.append(.people(manual: false)) } label: { Label("Check on someone", systemImage: "phone.fill") }
                    .buttonStyle(ActionStyle(primary: store.draft == nil))
                Button { path.append(.suggestions) } label: { Label("Suggest someone", systemImage: "person.crop.circle.badge.questionmark") }
                    .buttonStyle(ActionStyle(primary: false))
                Button { request(.people(true)) } label: { Label("Record a check", systemImage: "square.and.pencil") }
                    .buttonStyle(ActionStyle(primary: false))
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("My follow-ups")
                if let item = openFollowUps.first { followUpButton(item) }
                else { Text("No follow-ups right now.") }
            }
            Button { path.append(.history) } label: {
                ActionRow(title: "Recent checks", subtitle: store.checks.isEmpty ? "No checks recorded yet" : "\(store.checks.count) saved on this iPhone")
            }.buttonStyle(RowActionStyle())
        }.navigationTitle("Buddy Checks")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Account and Post settings", systemImage: "person.crop.circle", action: openSettings)
            } }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .suggestions: SuggestionsScreen(store: store, session: suggestions) { path.append(.person($0)) }
        case .people(let manual): people(manual: manual)
        case .contacts(let id):
            if let person = store.person(id) { ContactsScreen(person: person, post: post, store: store) }
            else { Page { unavailable("Person unavailable") } }
        case .person(let id): personDetail(id)
        case .draft: draftScreen
        case .check(let id): checkDetail(id)
        case .history: history
        case .followUp(let id): followUpDetail(id)
        case .reschedule(let id): reschedule(id)
        }
    }
    private func people(manual: Bool) -> some View {
        Page {
            SectionTitle(manual ? "Who did you check on?" : "Who will you check on?")
            if !manual {
                Button("Suggest someone") { path.append(.suggestions) }.buttonStyle(ActionStyle(primary: false))
            }
            TextField("Search by name", text: $search, prompt: Text("Search by name").foregroundStyle(Palette.ink.opacity(0.75)))
                .textFieldStyle(.plain).frame(minHeight: 48).padding(.horizontal, 14)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
                .accessibilityLabel("Search by name")
            let matches = store.people.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            if matches.isEmpty {
                Text("No matching names. Try a first or last name.")
                Button("Clear search") { search = "" }.buttonStyle(ActionStyle(primary: false))
            }
            VStack(spacing: 12) {
                ForEach(matches) { person in
                    Button {
                        if manual { request(.start(person.id, .manual)) } else { path.append(.person(person.id)) }
                    } label: { ActionRow(title: person.name) }.buttonStyle(RowActionStyle())
                }
            }
        }.navigationTitle(manual ? "Record a check" : "Check on someone")
    }
    private func personDetail(_ id: UUID) -> some View {
        Page {
            if let person = store.person(id) {
                PersonCard(person: person)
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("A way to start")
                    Text("“Hi \(person.firstName), I'm checking in from the Post. How have you been?”")
                }.padding(20).background(Palette.paper, in: RoundedRectangle(cornerRadius: 16))
                // Synthetic fixtures never pass a telephone URL to the system.
                if person.isSynthetic {
                    Button("Simulate call with \(person.firstName)") { request(.start(id, .simulatedCall)) }.buttonStyle(ActionStyle())
                }
                Button("Record a check") { request(.start(id, .manual)) }.buttonStyle(ActionStyle(primary: false))
                Button(store.contactLink(for: person) == nil ? "Add to Contacts" : "Phone contact") { path.append(.contacts(id)) }.buttonStyle(ActionStyle(primary: false))
            } else { unavailable("Person unavailable") }
        }.navigationTitle("Buddy Check")
    }

    private var draftScreen: some View {
        Page {
            if let draft = store.draft, let person = store.person(draft.personID) {
                PersonCard(person: person)
                switch draft.stage {
                case .details: details(draft)
                case .outcome: outcome(draft)
                case .reminder: reminder(draft)
                }
                Button("Discard unfinished check", role: .destructive) { showDiscard = true }
                    .font(.headline).foregroundStyle(Palette.red).frame(minHeight: 48)
            } else { unavailable("Unfinished check unavailable") }
        }.navigationTitle(store.draft?.origin == .correction ? "Correct check" : "Record a check")
    }
    private func draftBinding<Value>(_ draft: CheckDraft, _ key: WritableKeyPath<CheckDraft, Value>) -> Binding<Value> {
        Binding(get: { (store.draft ?? draft)[keyPath: key] }, set: { value in
            perform { try store.updateDraft(id: draft.id) { $0[keyPath: key] = value; $0.eventTimeZone = TimeZone.current.identifier } }
        })
    }
    private func details(_ draft: CheckDraft) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionTitle("How did you check in?")
            VStack(spacing: 12) {
                ForEach(ContactMethod.allCases) { method in
                    Button { perform { try store.setMethod(id: draft.id, method: method) } } label: {
                        Label(method.label, systemImage: draft.method == method ? "checkmark.circle.fill" : "circle")
                    }.buttonStyle(ActionStyle(primary: draft.method == method))
                        .accessibilityAddTraits(draft.method == method ? .isSelected : [])
                }
            }
            WorkingSurface {
                SectionTitle("When did it happen?")
                DateTimeFields(selection: draftBinding(draft, \.occurredAt), future: false)
                Text("Times shown in \(timeZoneText()).").font(.footnote)
                if draft.eventTimeZone != TimeZone.current.identifier { Text("Originally entered in \(timeZoneText(draft.eventTimeZone)).").font(.footnote) }
            }
            Button("Continue") { perform { try store.finishDetails(id: draft.id) } }.buttonStyle(ActionStyle())
        }
    }
    private func outcome(_ draft: CheckDraft) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionTitle("What happened?")
            VStack(spacing: 12) {
                ForEach(CheckOutcome.choices(for: draft.method)) { choice in
                    Button { perform { try store.updateDraft(id: draft.id) { $0.outcome = choice } } } label: {
                        Label(choice.label(for: draft.method), systemImage: draft.outcome == choice ? "checkmark.circle.fill" : "circle")
                    }.buttonStyle(ActionStyle(primary: draft.outcome == choice))
                        .accessibilityAddTraits(draft.outcome == choice ? .isSelected : [])
                }
            }
            Button { perform { try store.updateDraft(id: draft.id) { $0.stage = .details } } } label: {
                ActionRow(title: "Change method or time", subtitle: "\(draft.method.label) · \(dateText(draft.occurredAt))")
            }.buttonStyle(RowActionStyle())
            if draft.outcome != nil {
                if draft.origin == .correction {
                    Button("Save correction") { save(draft.id, followUp: false) }.buttonStyle(ActionStyle())
                } else {
                    Button("Add follow-up") { perform { try store.chooseReminder(id: draft.id, timeZone: TimeZone.current.identifier) } }.buttonStyle(ActionStyle())
                    Button("Save without follow-up") { save(draft.id, followUp: false) }.buttonStyle(ActionStyle(primary: false))
                }
            }
        }
    }
    private func reminder(_ draft: CheckDraft) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkingSurface {
                SectionTitle("When will you follow up?")
                DateTimeFields(selection: Binding(get: { store.draft?.followUpDue ?? Date() }, set: { value in
                    perform { try store.updateDraft(id: draft.id) { $0.followUpDue = value; $0.followUpTimeZone = TimeZone.current.identifier } }
                }), future: true)
                Text("\(timeZoneText()). This stays at the same moment if you travel.").font(.footnote)
                Text("After saving, you can add a phone reminder from your follow-up.").font(.subheadline)
            }
            Button("Save check and follow-up") { save(draft.id, followUp: true) }.buttonStyle(ActionStyle())
            Button("Save without follow-up") { save(draft.id, followUp: false) }.buttonStyle(ActionStyle(primary: false))
            Button("Change outcome") { perform { try store.updateDraft(id: draft.id) { $0.stage = .outcome } } }.buttonStyle(ActionStyle(primary: false))
        }
    }

    private var history: some View {
        Page {
            SectionTitle("Recent checks")
            if store.checks.isEmpty { Text("Your saved checks will appear here.") }
            VStack(spacing: 12) {
                ForEach(store.checks) { check in
                    Button { path.append(.check(check.id)) } label: {
                        ActionRow(title: store.person(check.personID)?.name ?? "Person unavailable", subtitle: "\(check.outcome.label(for: check.method)) · \(dateText(check.occurredAt))")
                    }.buttonStyle(RowActionStyle())
                }
            }
        }.navigationTitle("Recent checks")
    }
    private func checkDetail(_ id: UUID) -> some View {
        Page {
            if let check = store.check(id), let person = store.person(check.personID) {
                PersonCard(person: person)
                WorkingSurface {
                    Label("Check recorded", systemImage: "checkmark.circle.fill").font(.headline)
                    Text(check.outcome.label(for: check.method)).font(.title2.bold())
                    Text("\(check.method.label) · \(dateText(check.occurredAt))")
                    Text("\(timeZoneText()) · \(check.storageLabel)").font(.footnote)
                    Text("Recorded \(dateText(check.recordedAt))").font(.footnote)
                    if !check.revisions.isEmpty { Text("Corrected \(dateText(check.updatedAt))").font(.footnote) }
                }
                if let followUp = store.followUp(forCheck: id) { followUpButton(followUp) }
                Button("Correct this check") { request(.correction(id)) }.buttonStyle(ActionStyle(primary: false))
                Button("Back to Home") { goHome() }.buttonStyle(ActionStyle())
            } else { unavailable("Check unavailable") }
        }.navigationTitle("Your check")
    }
    private func followUpButton(_ item: FollowUp) -> some View {
        Button { path.append(.followUp(item.id)) } label: {
            ActionRow(title: store.person(item.personID)?.name ?? "Person unavailable", subtitle: "\(item.status == .open ? "Follow up" : item.status.rawValue.capitalized) · \(dateText(item.due))")
        }.buttonStyle(RowActionStyle())
    }
    private var followUpList: some View {
        Page {
            SectionTitle("My follow-ups")
            if openFollowUps.isEmpty { Text("No follow-ups right now.") }
            VStack(spacing: 12) { ForEach(openFollowUps) { followUpButton($0) } }
            let closed = store.followUps.filter { $0.status != .open }
            if !closed.isEmpty {
                SectionTitle("Closed")
                VStack(spacing: 12) { ForEach(closed) { followUpButton($0) } }
            }
        }.navigationTitle("Follow-ups")
    }
    private func followUpDetail(_ id: UUID) -> some View {
        Page {
            if let item = store.followUp(id), let person = store.person(item.personID) {
                PersonCard(person: person)
                WorkingSurface {
                    SectionTitle(item.status == .open ? "Follow up" : item.status.rawValue.capitalized)
                    Text(dateText(item.due)).font(.title3)
                    Text(timeZoneText()).font(.footnote)
                }
                if item.status == .open {
                    DeviceReminderControls(item: item, reminders: reminders)
                    Button("Record a check") { request(.start(person.id, .manual)) }.buttonStyle(ActionStyle())
                    Button("Mark complete") { perform { try store.closeFollowUp(id: id, status: .completed) } }.buttonStyle(ActionStyle(primary: false))
                    Button("Change time") { editingDate = item.due; path.append(.reschedule(id)) }.buttonStyle(ActionStyle(primary: false))
                    Button("Cancel follow-up", role: .destructive) { cancelFollowUpID = id }.font(.headline).foregroundStyle(Palette.red).frame(minHeight: 48)
                    Text("Mark complete closes the follow-up without recording another conversation.").font(.footnote)
                }
                Button("View original check") { path.append(.check(item.checkID)) }.buttonStyle(ActionStyle(primary: false))
            } else { unavailable("Follow-up unavailable") }
        }.navigationTitle("Your follow-up")
    }
    private func reschedule(_ id: UUID) -> some View {
        Page {
            if let item = store.followUp(id), let person = store.person(item.personID) {
                PersonCard(person: person)
                WorkingSurface {
                    SectionTitle("Change follow-up time")
                    DateTimeFields(selection: $editingDate, future: true)
                    Text(timeZoneText()).font(.footnote)
                }
                Button("Save new time") {
                    perform { try store.rescheduleFollowUp(id: id, due: editingDate, timeZone: TimeZone.current.identifier); path.removeLast() }
                }.buttonStyle(ActionStyle())
            } else { unavailable("Follow-up unavailable") }
        }.navigationTitle("Change time")
    }
    private func unavailable(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionTitle(title)
            Text("This item is no longer available.")
            Button("Back to Home") { goHome() }.buttonStyle(ActionStyle())
        }
    }
}

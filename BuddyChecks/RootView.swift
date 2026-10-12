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
    private var openFollowUps: [FollowUp] { store.followUps.filter { $0.status == .open }.sorted { $0.due < $1.due } }

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
                        home(openSettings: openSettings, returnToPost: returnToPost).navigationDestination(for: Route.self, destination: destination)
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

    private func home(openSettings: @escaping () -> Void, returnToPost: (() -> Void)?) -> some View {
        Page(spacing: 0, topPadding: 0, decorated: true) {
            BuddyMasthead(post: post.shortName, openSettings: openSettings)
            if let returnToPost { Button("Back to Post", action: returnToPost).frame(minHeight: 48) }
            SectionBand(color: Palette.context) {
                if let draft = store.draft, let person = store.person(draft.personID) {
                    Text("Unfinished check").font(.subheadline)
                    PersonCard(person: person)
                    Button("Continue with \(person.firstName)") { path = [.draft] }.buttonStyle(ActionStyle())
                } else {
                    if let item = openFollowUps.first, let person = store.person(item.personID) {
                        Text("Next follow-up").font(.subheadline)
                        PersonCard(person: person)
                        Text(dateText(item.due)).font(.subheadline)
                        Button("Open follow-up") { path.append(.followUp(item.id)) }.buttonStyle(ActionStyle())
                    } else {
                        PageInvitation(title: store.checks.isEmpty ? "Your first Buddy Check" : "Who will you check on?",
                                       detail: "Find someone by name, or try a suggested person.")
                    }
                    Button("Choose a member") { search = ""; path.append(.people(manual: false)) }
                        .buttonStyle(ActionStyle(primary: openFollowUps.isEmpty))
                }
                Text("Practice with synthetic people. No calls are placed.").font(.footnote).foregroundStyle(.secondary)
            }
            SectionBand(spacing: 10) {
                HStack {
                    SectionTitle("Recent checks")
                    Spacer()
                    Button("Your checks") { path.append(.history) }.font(.subheadline).buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
                if store.checks.isEmpty { Text("Your saved checks will appear here.").foregroundStyle(.secondary) }
                ForEach(Array(store.checks.sorted { $0.updatedAt > $1.updatedAt }.prefix(3))) { check in
                    Button { path.append(.check(check.id)) } label: {
                        HStack(spacing: 12) {
                            PersonAvatar(name: store.person(check.personID)?.name ?? "?", size: 41)
                            ActionRow(title: store.person(check.personID)?.name ?? "Person unavailable", subtitle: check.outcome.label(for: check.method) + " · " + dateText(check.occurredAt))
                        }
                    }.buttonStyle(RowActionStyle())
                }
            }
        }.navigationTitle("Buddy Checks").toolbar(.hidden, for: .navigationBar)
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
        Page(spacing: 0, topPadding: 0) {
            SectionBand(color: Palette.context) {
                Text(manual ? "Who did you check on?" : "Who’s on your mind?").font(.title.bold())
                TextField("Search by name", text: $search)
                    .textFieldStyle(.plain).frame(minHeight: 48).padding(.horizontal, 14)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Search by name")
                if !manual { Button("Suggest someone") { path.append(.suggestions) }.buttonStyle(ActionStyle(primary: false)) }
            }
            SectionBand(spacing: 0) {
                let matches = store.people.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                if matches.isEmpty {
                    Text("No matching names. Try a first or last name.")
                    Button("Clear search") { search = "" }.buttonStyle(ActionStyle(primary: false))
                }
                ForEach(matches) { person in
                    Button {
                        if manual { request(.start(person.id, .manual)) } else { path.append(.person(person.id)) }
                    } label: {
                        HStack(spacing: 12) { PersonAvatar(name: person.name, size: 42); ActionRow(title: person.name) }
                    }.buttonStyle(RowActionStyle())
                }
            }
        }.navigationTitle("Choose a member")
    }
    private func personDetail(_ id: UUID) -> some View {
        Page(spacing: 0, topPadding: 0) {
            if let person = store.person(id) {
                MemberProfile(name: person.name, subtitle: "Synthetic practice contact")
                SectionBand {
                    // Synthetic fixtures never pass a telephone URL to the system.
                    if person.isSynthetic {
                        Button("Simulate call with \(person.firstName)") { request(.start(id, .simulatedCall)) }.buttonStyle(ActionStyle())
                    }
                    Button("Record a check") { request(.start(id, .manual)) }.buttonStyle(ActionStyle(primary: false))
                }
                ConversationPrompt(firstName: person.firstName)
                Button { path.append(.contacts(id)) } label: {
                    ActionRow(title: store.contactLink(for: person) == nil ? "Add to Contacts" : "Phone contact")
                }.buttonStyle(RowActionStyle())
            } else { unavailable("Person unavailable") }
        }.navigationTitle("Buddy Check")
            .toolbarBackground(Palette.navy, for: .navigationBar).toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var draftScreen: some View {
        Page {
            if let draft = store.draft, let person = store.person(draft.personID) {
                SectionBand(color: Palette.context) { PersonCard(person: person) }
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
            VStack(spacing: 0) {
                ForEach(ContactMethod.allCases) { method in
                    Button { perform { try store.setMethod(id: draft.id, method: method) } } label: {
                        Label(method.label, systemImage: draft.method == method ? "checkmark.circle.fill" : "circle")
                    }.buttonStyle(ChoiceStyle(selected: draft.method == method))
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
            VStack(spacing: 0) {
                ForEach(CheckOutcome.choices(for: draft.method)) { choice in
                    Button { perform { try store.updateDraft(id: draft.id) { $0.outcome = choice } } } label: {
                        Label(choice.label(for: draft.method), systemImage: draft.outcome == choice ? "checkmark.circle.fill" : "circle")
                    }.buttonStyle(ChoiceStyle(selected: draft.outcome == choice))
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
        Page(spacing: 20, topPadding: 0) {
            if let check = store.check(id), let person = store.person(check.personID) {
                ConfirmationHeading(title: "Check recorded", name: person.name)
                VStack(spacing: 0) {
                    ReceiptRow(title: "Outcome", value: check.outcome.label(for: check.method))
                    ReceiptRow(title: "Contact", value: "\(check.method.label) · \(dateText(check.occurredAt))")
                    Text("\(timeZoneText()) · \(check.storageLabel)").font(.footnote).padding(.vertical, 12)
                    if !check.revisions.isEmpty { Text("Corrected \(dateText(check.updatedAt))").font(.footnote) }
                }.padding(.horizontal, 18).padding(.bottom, 12).background(.white)
                if let followUp = store.followUp(forCheck: id) { followUpButton(followUp) }
                Button("Back to Home") { goHome() }.buttonStyle(ActionStyle())
                Button("Correct this check") { request(.correction(id)) }.buttonStyle(ActionStyle(primary: false))
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
                SectionBand(color: Palette.context) {
                    PersonCard(person: person)
                    HStack(spacing: 14) {
                        CalendarStamp(date: item.due)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(dateText(item.due)).font(.headline)
                            Text(item.status == .open ? "Follow up" : item.status.rawValue.capitalized).font(.subheadline)
                        }
                    }
                }
                if item.status == .open {
                    Button("Record a check") { request(.start(person.id, .manual)) }.buttonStyle(ActionStyle())
                    SectionBand { DeviceReminderControls(item: item, reminders: reminders) }
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

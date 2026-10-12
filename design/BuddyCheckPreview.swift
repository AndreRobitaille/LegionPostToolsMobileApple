import SwiftUI
import Observation

// A disposable, in-memory design preview. No phone, network, storage or
// notification APIs are used. Production workflow behavior belongs in M1.
private enum Palette {
    static let navy = Color(red: 10 / 255, green: 34 / 255, blue: 64 / 255)
    static let canvas = Color(red: 240 / 255, green: 242 / 255, blue: 245 / 255)
    static let surface = Color.white
    static let action = Color(red: 20 / 255, green: 102 / 255, blue: 204 / 255)
    static let actionSurface = Color(red: 227 / 255, green: 238 / 255, blue: 255 / 255)
    static let actionInk = Color(red: 16 / 255, green: 79 / 255, blue: 156 / 255)
    static let border = Color(red: 123 / 255, green: 135 / 255, blue: 152 / 255)
    static let paper = Color(red: 251 / 255, green: 247 / 255, blue: 236 / 255)
    static let gold = Color(red: 198 / 255, green: 161 / 255, blue: 91 / 255)
    static let ink = Color(red: 27 / 255, green: 34 / 255, blue: 43 / 255)
    static let red = Color(red: 140 / 255, green: 22 / 255, blue: 34 / 255)
}

private struct Person: Identifiable, Hashable {
    let id: String
    let name: String
    var firstName: String { String(name.split(separator: " ")[0]) }
    static let examples = [
        Person(id: "robert", name: "Robert Miller"),
        Person(id: "elena", name: "Elena Davis"),
        Person(id: "james", name: "James Wilson")
    ]
}

private enum Outcome: String, CaseIterable, Identifiable {
    case talked = "We talked"
    case noAnswer = "No answer"
    case wrongNumber = "Wrong number"
    case didNotCall = "I didn't call"
    var id: String { rawValue }
}

private enum Screen: String, Hashable {
    case people, person, outcome, reminder, changeTime, saved, followups, followup
}

private enum MainTab: Hashable { case home, followups }

private struct FollowUp: Identifiable {
    let id: UUID
    let person: Person
    var due: Date
    var status = "Open"
}

private struct ActionStyle: ButtonStyle {
    var primary = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 16).padding(.vertical, 15)
            .foregroundStyle(primary ? Palette.surface : Palette.actionInk)
            .background(primary ? Palette.action : Palette.actionSurface,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Palette.action, lineWidth: 1.25))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct RowActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.actionInk)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.actionSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Palette.action, lineWidth: 1.25))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

@main
struct BuddyCheckPreviewApp: App {
    var body: some Scene {
        WindowGroup {
            PreviewRoot()
                .tint(Palette.action)
        }
    }
}

@MainActor @Observable
private final class PreviewSession {
    var selectedTab: MainTab = .home
    var path: [Screen] = []
    var followupPath: [Screen] = []
    var person = Person.examples[0]
    var outcome: Outcome?
    var draft = false
    var search = ""
    var selectedDate = PreviewRoot.fixtureDate()
    var editingDate = PreviewRoot.fixtureDate()
    var homeEditingDate = PreviewRoot.fixtureDate()
    var followups = [FollowUp(id: UUID(), person: Person.examples[1], due: PreviewRoot.fixtureDate())]
    var currentFollowUpID: UUID?
    var homeFollowUpID: UUID?
    var savedOutcome: Outcome = .talked
    var savedPerson = Person.examples[0]
    var savedFollowUpID: UUID?
    var correcting = false
    var showDiscard = false
    var showCancel = false
    var dateError = false
    var deniedExample = false

}

private struct PreviewRoot: View {
    @Environment(\.dynamicTypeSize) private var systemTextSize
    @State private var session = PreviewSession()
    private var path: [Screen] {
        get { session.selectedTab == .home ? session.path : session.followupPath }
        nonmutating set {
            if session.selectedTab == .home { session.path = newValue }
            else { session.followupPath = newValue }
        }
    }
    private var person: Person {
        get { session.person }
        nonmutating set { session.person = newValue }
    }
    private var outcome: Outcome? {
        get { session.outcome }
        nonmutating set { session.outcome = newValue }
    }
    private var draft: Bool {
        get { session.draft }
        nonmutating set { session.draft = newValue }
    }
    private var search: String {
        get { session.search }
        nonmutating set { session.search = newValue }
    }
    private var selectedDate: Date {
        get { session.selectedDate }
        nonmutating set { session.selectedDate = newValue }
    }
    private var followups: [FollowUp] {
        get { session.followups }
        nonmutating set { session.followups = newValue }
    }
    private var currentFollowUpID: UUID? {
        get { session.selectedTab == .home ? session.homeFollowUpID : session.currentFollowUpID }
        nonmutating set {
            if session.selectedTab == .home { session.homeFollowUpID = newValue }
            else { session.currentFollowUpID = newValue }
        }
    }
    private var savedOutcome: Outcome {
        get { session.savedOutcome }
        nonmutating set { session.savedOutcome = newValue }
    }
    private var savedPerson: Person {
        get { session.savedPerson }
        nonmutating set { session.savedPerson = newValue }
    }
    private var savedFollowUpID: UUID? {
        get { session.savedFollowUpID }
        nonmutating set { session.savedFollowUpID = newValue }
    }
    private var editingFollowUp: Bool { path.last == .changeTime }
    private var editingDate: Date {
        get { session.selectedTab == .home ? session.homeEditingDate : session.editingDate }
        nonmutating set {
            if session.selectedTab == .home { session.homeEditingDate = newValue }
            else { session.editingDate = newValue }
        }
    }
    private var correcting: Bool {
        get { session.correcting }
        nonmutating set { session.correcting = newValue }
    }
    private var showDiscard: Bool {
        get { session.showDiscard }
        nonmutating set { session.showDiscard = newValue }
    }
    private var showCancel: Bool {
        get { session.showCancel }
        nonmutating set { session.showCancel = newValue }
    }
    private var dateError: Bool {
        get { session.dateError }
        nonmutating set { session.dateError = newValue }
    }
    private var deniedExample: Bool {
        get { session.deniedExample }
        nonmutating set { session.deniedExample = newValue }
    }

    private var reminderPerson: Person { editingFollowUp ? currentFollowUp?.person ?? person : person }
    private var reminderDate: Date { editingFollowUp ? editingDate : selectedDate }
    private var reminderDateBinding: Binding<Date> {
        Binding(get: { reminderDate }, set: { value in
            if editingFollowUp { editingDate = value } else { selectedDate = value }
        })
    }

    private static let chicago = TimeZone(identifier: "America/Chicago")!
    private var currentFollowUp: FollowUp? { followups.first { $0.id == currentFollowUpID } }
    private var savedFollowUp: FollowUp? { followups.first { $0.id == savedFollowUpID } }
    private var openFollowups: [FollowUp] { followups.filter { $0.status == "Open" }.sorted { $0.due < $1.due } }
    private var requestedSize: DynamicTypeSize? {
        if ProcessInfo.processInfo.arguments.contains("--accessibility-max") { return .accessibility5 }
        if ProcessInfo.processInfo.arguments.contains("--accessibility") { return .accessibility3 }
        return nil
    }
    private var usesAccessibilityText: Bool { (requestedSize ?? systemTextSize).isAccessibilitySize }

    static func fixtureDate() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = chicago
        let day = calendar.date(byAdding: .day, value: 4, to: Date())!
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
    }

    private func dueText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = Self.chicago
        formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        return formatter.string(from: date)
    }

    var body: some View {
        TabView(selection: $session.selectedTab) {
            NavigationStack(path: $session.path) {
                home
                    .navigationDestination(for: Screen.self) { screen in
                        destination(screen)
                    }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(MainTab.home)

            NavigationStack(path: $session.followupPath) {
                followupList
                    .navigationDestination(for: Screen.self) { screen in
                        destination(screen)
                    }
            }
            .tabItem { Label("Follow-ups", systemImage: "calendar") }
            .tag(MainTab.followups)
        }
        .tint(Palette.action)
        .background(Palette.canvas)
        .environment(\.dynamicTypeSize, requestedSize ?? systemTextSize)
        .confirmationDialog("A check is unfinished", isPresented: $session.showDiscard, titleVisibility: .visible) {
            Button("Continue with \(person.firstName)") { path = [.outcome] }
            Button("Discard and choose someone", role: .destructive) { draft = false; outcome = nil; path = [.people] }
            Button("Keep unfinished check", role: .cancel) {}
        }
        .confirmationDialog("Cancel this follow-up?", isPresented: $session.showCancel, titleVisibility: .visible) {
            Button("Cancel follow-up", role: .destructive) { updateStatus("Cancelled") }
            Button("Keep follow-up", role: .cancel) {}
        } message: { Text("The check stays recorded. Only the follow-up is cancelled.") }
        .onAppear { openLaunchScenario() }
    }

    private func page<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24, content: content)
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, usesAccessibilityText ? 16 : 24)
                .padding(.top, 24).padding(.bottom, 32)
                .frame(maxWidth: .infinity)
                .tint(Palette.action)
                .environment(\.colorScheme, .light)
        }
        .background(Palette.canvas)
        .foregroundStyle(Palette.ink)
        .tint(Palette.surface)
        .toolbarBackground(Palette.navy, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.title2.bold()).foregroundStyle(Palette.navy)
            .accessibilityAddTraits(.isHeader)
    }

    private func personHeading(_ contact: Person) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Palette.gold).frame(width: 44, height: 4).accessibilityHidden(true)
            Text(contact.name).font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .foregroundStyle(Palette.surface)
            .background(Palette.navy, in: RoundedRectangle(cornerRadius: 16))
    }

    private func workingSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var home: some View {
        page {
            VStack(alignment: .leading, spacing: 6) {
                Text("Post 165").font(.largeTitle.bold()).foregroundStyle(Palette.navy)
                Text("Robert E. Burns · Two Rivers").font(.subheadline)
            }
            if draft {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Unfinished check", systemImage: "pencil").font(.subheadline)
                    Text(person.name).font(.title2.bold())
                    Button("Continue with \(person.firstName)") { path = [.outcome] }.buttonStyle(ActionStyle())
                }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Palette.gold).frame(width: 4).padding(.vertical, 16) }
            }
            Button {
                if draft { showDiscard = true } else { path = [.people] }
            } label: { Label("Check on someone", systemImage: "phone.fill") }
                .buttonStyle(ActionStyle(primary: !draft))
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("My follow-ups")
                if let item = openFollowups.first {
                    Button { showFollowups(detail: true); currentFollowUpID = item.id } label: {
                        followupRow(item)
                    }.buttonStyle(RowActionStyle())
                    Button("View all follow-ups") { showFollowups() }.buttonStyle(ActionStyle(primary: false))
                } else {
                    Text("No follow-ups right now.")
                    Button("View follow-ups") { showFollowups() }.buttonStyle(ActionStyle(primary: false))
                }
            }
        }.navigationTitle("Buddy Checks")
    }

    @ViewBuilder private func destination(_ screen: Screen) -> some View {
        switch screen {
        case .people: people
        case .person: contact
        case .outcome: outcomeScreen
        case .reminder, .changeTime: reminder
        case .saved: saved
        case .followups: followupList
        case .followup: followupDetail
        }
    }

    private var people: some View {
        page {
            sectionTitle("Who will you check on?")
            TextField("Search by name", text: $session.search,
                      prompt: Text("Search by name").foregroundStyle(Palette.ink.opacity(0.75)))
                .textFieldStyle(.plain).frame(minHeight: 48).padding(.horizontal, 14)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
                .accessibilityLabel("Search by name")
            let matches = Person.examples.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            if matches.isEmpty {
                Text("No matching names. Try a first or last name.")
                Button("Clear search") { search = "" }.buttonStyle(ActionStyle(primary: false))
            }
            VStack(spacing: 12) {
                ForEach(matches) { item in
                    Button {
                        person = item; outcome = nil; correcting = false; path.append(.person)
                    } label: {
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.name).font(.title3.bold())
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }.frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(RowActionStyle())
                }
            }
        }.navigationTitle("Check on someone")
    }

    private var contact: some View {
        page {
            personHeading(person)
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("A way to start")
                Text("“Hi \(person.firstName), I'm checking in from the Post. How have you been?”")
            }.padding(20).background(Palette.paper, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 12) {
                Button("Simulate call with \(person.firstName)") {
                    draft = true; path.append(.outcome)
                }.buttonStyle(ActionStyle())
            }
        }.navigationTitle("Buddy Check")
    }

    private var outcomeScreen: some View {
        page {
            personHeading(person)
            sectionTitle("How did it go?")
            VStack(spacing: 10) {
                ForEach(Outcome.allCases) { option in
                    Button { outcome = option; draft = true } label: {
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: outcome == option ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                            Text(option.rawValue).font(.headline)
                            Spacer(minLength: 0)
                        }.padding(16).frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .foregroundStyle(outcome == option ? Palette.surface : Palette.actionInk)
                            .background(outcome == option ? Palette.action : Palette.actionSurface,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(Palette.action, lineWidth: 1.25))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(outcome == option ? [.isSelected] : [])
                }
            }
            if outcome == .wrongNumber {
                Text("This records the problem. It doesn't change anyone's contact information.").font(.subheadline)
            } else if outcome == .didNotCall {
                Text("This won't be counted as a call attempt.").font(.subheadline)
            }
            if outcome != nil {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(correcting ? "Correct this check" : "What happens next?")
                    if correcting {
                        Text("Your follow-up stays as it is.").font(.subheadline)
                        Button("Save correction") { saveCheck(withReminder: false) }.buttonStyle(ActionStyle())
                    } else {
                        Button("Remind me to call again") {
                            dateError = false; path.append(.reminder)
                        }.buttonStyle(ActionStyle())
                        Button("Nothing else needed") { saveCheck(withReminder: false) }.buttonStyle(ActionStyle(primary: false))
                    }
                }
            }
        }.navigationTitle(correcting ? "Correct outcome" : "Record outcome")
    }

    private var reminder: some View {
        page {
            personHeading(reminderPerson)
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(editingFollowUp ? "Change the time" : "Call again")
                if !editingFollowUp, let outcome { Text(outcome.rawValue).font(.subheadline) }
            }
            VStack(alignment: .leading, spacing: 16) {
                if usesAccessibilityText {
                    Text("Day").font(.headline)
                    DatePicker("Day", selection: reminderDateBinding, displayedComponents: .date)
                        .labelsHidden()
                    Divider()
                    Text("Time").font(.headline)
                    DatePicker("Time", selection: reminderDateBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                } else {
                    DatePicker("Day", selection: reminderDateBinding, displayedComponents: .date)
                    Divider()
                    DatePicker("Time", selection: reminderDateBinding, displayedComponents: .hourAndMinute)
                }
            }.datePickerStyle(.compact).environment(\.timeZone, Self.chicago)
                .padding(usesAccessibilityText ? 8 : 20)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
            Text("Chicago time. Keeps the same moment when you travel.").font(.subheadline)
            if deniedExample {
                Label("No phone alert. Find this in My follow-ups.", systemImage: "bell.slash")
            }
            if dateError {
                Text("Choose a future date and time.").foregroundStyle(Palette.red)
                    .accessibilityAddTraits(.isStaticText)
            }
            Button(editingFollowUp ? "Save new time" : "Save check") {
                guard reminderDate > Date() else { dateError = true; return }
                if editingFollowUp {
                    if let index = followups.firstIndex(where: { $0.id == currentFollowUpID }) {
                        followups[index].due = reminderDate
                    }
                    path.removeLast()
                } else { saveCheck(withReminder: true) }
            }.buttonStyle(ActionStyle())
        }.navigationTitle("Follow-up")
    }

    private var saved: some View {
        page {
            Label("Check recorded", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(Palette.navy)
                .accessibilityAddTraits(.isHeader)
            personHeading(savedPerson)
            workingSurface {
                Text(savedOutcome.rawValue).font(.title2.bold())
                if let item = savedFollowUp {
                    Text(item.status == "Open" ? "Call again" : "Follow-up \(item.status.lowercased())").font(.headline)
                    Text(dueText(item.due))
                    Text("Chicago time").font(.subheadline)
                } else { Text("Nothing else needed.") }
            }
            VStack(spacing: 12) {
                Button("Done") { showHome() }.buttonStyle(ActionStyle())
                Button("Correct outcome") {
                    person = savedPerson; outcome = savedOutcome; correcting = true; path.append(.outcome)
                }.buttonStyle(ActionStyle(primary: false))
                if let item = savedFollowUp {
                    Button("View follow-up") { currentFollowUpID = item.id; path.append(.followup) }
                        .buttonStyle(ActionStyle(primary: false))
                }
            }
        }.navigationTitle("Check recorded")
    }

    private func followupRow(_ item: FollowUp) -> some View {
        HStack(spacing: 16) {
            if !usesAccessibilityText {
                Image(systemName: "phone.arrow.up.right")
                    .font(.title2).foregroundStyle(Palette.actionInk)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(item.person.name).font(.title3.bold())
                Text(dueText(item.due)).font(.subheadline)
                Text(item.status == "Open" ? "Call again · Chicago time" : item.status).font(.footnote)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").accessibilityHidden(true)
        }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }

    private var followupList: some View {
        page {
            sectionTitle("Calls to return to")
            if openFollowups.isEmpty { Text("No open follow-ups.").font(.title3) }
            VStack(spacing: 12) {
                ForEach(openFollowups) { item in
                    Button { currentFollowUpID = item.id; path.append(.followup) } label: { followupRow(item) }
                        .buttonStyle(RowActionStyle())
                }
            }
            let closed = followups.filter { $0.status != "Open" }
            if !closed.isEmpty {
                sectionTitle("Finished")
                ForEach(closed) { item in
                    Button { currentFollowUpID = item.id; path.append(.followup) } label: { followupRow(item) }
                        .buttonStyle(RowActionStyle())
                }
            }
        }.navigationTitle("My follow-ups")
    }

    private var followupDetail: some View {
        page {
            if let item = currentFollowUp {
                personHeading(item.person)
                workingSurface {
                    sectionTitle("Call again")
                    Text(dueText(item.due)).font(.title3)
                    Text("Chicago time").font(.subheadline)
                    if item.status != "Open" {
                        Label(item.status, systemImage: "checkmark.circle")
                    }
                }
                if item.status == "Open" {
                    VStack(spacing: 12) {
                        Button("Mark complete") { updateStatus("Completed") }.buttonStyle(ActionStyle())
                        Button("Change time") {
                            editingDate = item.due
                            dateError = false; deniedExample = false; path.append(.changeTime)
                        }.buttonStyle(ActionStyle(primary: false))
                        Button("Cancel follow-up", role: .destructive) { showCancel = true }
                            .font(.headline).foregroundStyle(Palette.red).frame(minHeight: 48)
                    }
                    Text("Marking this complete closes the follow-up. It doesn't record another conversation.").font(.footnote)
                } else {
                    Text("This follow-up is \(item.status.lowercased()). No further action is scheduled.")
                    Button("My follow-ups") { showFollowups() }.buttonStyle(ActionStyle())
                }
            } else {
                sectionTitle("Follow-up unavailable")
                Text("This follow-up is no longer available.")
                Button("My follow-ups") { showFollowups() }.buttonStyle(ActionStyle())
            }
        }.navigationTitle("Your follow-up")
    }

    private func saveCheck(withReminder: Bool) {
        guard let outcome else { return }
        savedOutcome = outcome; savedPerson = person
        if !correcting {
            savedFollowUpID = nil
            if withReminder {
                let item = FollowUp(id: UUID(), person: person, due: selectedDate)
                followups.append(item); savedFollowUpID = item.id
            }
        }
        correcting = false; draft = false
        path = [.saved]
    }

    private func updateStatus(_ status: String) {
        if let index = followups.firstIndex(where: { $0.id == currentFollowUpID }) {
            followups[index].status = status
        }
    }

    private func showHome() {
        session.selectedTab = .home
        session.path = []
    }

    private func showFollowups(detail: Bool = false) {
        session.selectedTab = .followups
        session.followupPath = detail ? [.followup] : []
    }

    private func openLaunchScenario() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--screen"), args.indices.contains(index + 1) else { return }
        let requested = args[index + 1]
        if requested == "followups" { showFollowups(); return }
        if requested == "resume" { draft = true; return }
        if requested == "denied" { deniedExample = true; outcome = .talked; path = [.reminder]; return }
        guard let screen = Screen(rawValue: requested) else { return }
        if [.reminder, .saved].contains(screen) { outcome = .talked }
        if screen == .saved {
            let item = FollowUp(id: UUID(), person: person, due: selectedDate)
            followups.append(item); savedFollowUpID = item.id
        }
        if screen == .followup { currentFollowUpID = followups.first?.id }
        path = [screen]
    }
}

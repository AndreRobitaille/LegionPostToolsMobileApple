import SwiftUI
import BuddyCheckCore

struct SuggestionsScreen: View {
    let store: CheckStore
    let session: SuggestionSession
    let choose: (UUID) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var error: String?
    @State private var choiceChanged = false
    @State private var evaluationTime = Date()

    var body: some View {
        let result = session.result(store: store)
        Page(scrollResetID: pageID(result)) {
            if choiceChanged {
                Text("That suggestion changed. Choose from the current suggestions below.")
                    .font(.callout).accessibilityAddTraits(.updatesFrequently)
            }
            switch result {
            case .person(let suggestion):
                if let person = store.person(suggestion.personID) {
                    PersonCard(person: person)
                    WorkingSurface {
                        ForEach(Array(suggestion.reasons.enumerated()), id: \.offset) { _, reason in reasonView(reason) }
                        if suggestion.incompleteHistory {
                            Text("Buddy Check history is incomplete.").font(.footnote)
                        }
                    }
                    VStack(spacing: 12) {
                        Button("Check on \(person.firstName)") {
                            if session.select(person.id, store: store) { choiceChanged = false; choose(person.id) }
                            else { choiceChanged = true }
                        }.buttonStyle(ActionStyle())
                        Button("Someone else") { choiceChanged = false; session.skip(person.id) }
                            .buttonStyle(ActionStyle(primary: false))

                    }
                }
            case .exhausted:
                empty("You've seen the suggestions", "Someone else keeps each person out of this round. Start again when you're ready to review them.")
                Button("Start again") { session.startAgain(); choiceChanged = false }.buttonStyle(ActionStyle())
            case .none:
                empty("No one to suggest right now", "Recent contact, open follow-ups, assignments and contact preferences can keep people out of this list.")
            case .insufficientEvidence:
                empty("More history is needed", "The available Buddy Check history and meeting registers aren't complete enough for a suggestion. Missing records don't mean someone was absent or hasn't been contacted.")
            case .stale:
                empty("Suggestions need a refresh", "These records are out of date. Refresh before choosing someone.")
                refreshButton
            case .failed:
                empty("Suggestions unavailable", "The records couldn't be loaded. Try again to get current suggestions.")
                refreshButton
            }
            let snoozes = store.snapshot.suggestionSnoozes.filter { $0.until > evaluationTime && store.person($0.personID) != nil }
            if !snoozes.isEmpty {
                DisclosureGroup("Hidden suggestions (\(snoozes.count))") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(snoozes, id: \.personID) { snooze in
                            if let person = store.person(snooze.personID) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(person.name).font(.headline)
                                    Text("Hidden until \(dateText(snooze.until))").font(.subheadline)
                                    Button("Show \(person.firstName) again") {
                                        change { try store.showSuggestionAgain(personID: person.id) }
                                    }.buttonStyle(ActionStyle(primary: false))
                                }
                            }
                        }
                    }.padding(.top, 12)
                }.foregroundStyle(Palette.ink).tint(Palette.action)
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { evaluationTime = $0 }
        .navigationTitle("Suggestions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { session.refresh(); choiceChanged = false } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Refresh suggestions")
            }
        }
        .onAppear { session.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { session.refresh() } }
        .alert("Couldn't show this person again", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "Your previous choice is unchanged.") }
    }
    private var refreshButton: some View {
        Button("Try again") { session.refresh(); choiceChanged = false }.buttonStyle(ActionStyle())
    }
    private func change(_ action: () throws -> Void) {
        do { try action() }
        catch { self.error = "The change couldn't be saved on this iPhone. Your previous choice is unchanged." }
    }
    private func empty(_ title: String, _ detail: String) -> some View {
        WorkingSurface { SectionTitle(title); Text(detail) }
    }
    @ViewBuilder private func reasonView(_ reason: SuggestionReason) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch reason {
            case .noChecks(let since):
                Text("No Buddy Check recorded").font(.headline)
                Text("Records since \(day(since))").font(.subheadline)
            case .noConversation(let since):
                Text("No conversation recorded").font(.headline)
                Text("Records since \(day(since))").font(.subheadline)
            case .lastConversation(let date):
                Text("Last recorded conversation").font(.headline)
                Text(day(date)).font(.subheadline)
            case .absentMeetings(let dates):
                Text("Absent at the last two meetings").font(.headline)
                Text(dates.map(day).joined(separator: " and ")).font(.subheadline)
                Text("Both attendance registers are complete.").font(.footnote)
            }
        }
    }
    private func day(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .omitted) }
    private func pageID(_ result: SuggestionResult) -> String {
        if case .person(let suggestion) = result { return suggestion.personID.uuidString }
        return String(describing: result)
    }
}

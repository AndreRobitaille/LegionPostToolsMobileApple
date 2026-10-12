import SwiftUI
import BuddyCheckAPI

private enum ConnectedRoute: Hashable { case search, suggestion, person(Int), draft, history, followUps, snoozes }

struct ConnectedMainView: View {
    let account: ConnectedAccount
    let session: MobileSession
    let openSettings: () -> Void
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                ConnectedHome(account: account, session: session).toolbar { settingsButton }
            }.tabItem { Label("Home", systemImage: "house") }.tag(0)
            NavigationStack {
                ConnectedFollowUps(account: account).toolbar { settingsButton }
            }.tabItem { Label("Follow-ups", systemImage: "calendar") }.tag(1)
        }
        .onChange(of: ReminderInbox.shared.link) { _, link in
            if link?.namespace.hasPrefix("connected.") == true { tab = 0 }
        }
    }
    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Account and Post settings", systemImage: "person.crop.circle", action: openSettings)
        }
    }
}

struct ConnectedHome: View {
    let account: ConnectedAccount
    let session: MobileSession
    @State private var route: ConnectedRoute?
    @State private var error: String?
    @State private var busy = false
    @State private var discardRejected = false
    @State private var reviewingCorrection = false
    @State private var reminderDestination: ConnectedReminderDestination?
    @State private var showingReminder = false
    @State private var readingReminder = false
    @State private var reminderError: String?
    var body: some View {
        Page {
            Text(session.installation.name).font(.largeTitle.bold()).foregroundStyle(Palette.navy)
            if let journal = account.journal {
                if journal.snapshot.pending != nil {
                    WorkingSurface {
                        SectionTitle(journal.rejection == nil ? "Submission pending" : "Submission not saved")
                        Text(journal.rejection == nil
                             ? "The Post has not confirmed this submission on your iPhone. Check its status before starting another."
                             : "The Post rejected this submission. Your proposed changes are still on this iPhone.")
                        if journal.canReviewStaleCorrection {
                            Button("Review latest check") { reviewingCorrection = true }.buttonStyle(ActionStyle())
                        } else { Button(busy ? "Checking…" : "Check submission") {
                            Task {
                                busy = true; defer { busy = false }
                                do { _ = try await account.perform { client, token in try await journal.reconcile(client: client, token: token) } }
                                catch { self.error = safeMessage(error) }
                            }
                        }.buttonStyle(ActionStyle()).disabled(busy) }
                        if journal.rejection != nil {
                            Button("Discard rejected submission", role: .destructive) { discardRejected = true }
                                .frame(minHeight: 48).foregroundStyle(Palette.red)
                        }
                    }
                } else if journal.snapshot.draft != nil {
                    Button { route = .draft } label: { ActionRow(title: "Continue unfinished check") }.buttonStyle(RowActionStyle())
                } else {
                    Button { route = .search } label: { ActionRow(title: "Check on someone", subtitle: "Search the Post member list") }.buttonStyle(RowActionStyle())
                    Button { route = .suggestion } label: { ActionRow(title: "Suggest someone", subtitle: "From Post records") }.buttonStyle(RowActionStyle())
                }
                if let receipt = journal.lastReceipt {
                    WorkingSurface {
                        Label("Saved to the Post", systemImage: "checkmark.circle.fill").font(.headline)
                        Text(dateText(receipt.acceptedAt))
                    }
                }
            }
            Button { route = .history } label: { ActionRow(title: "Your checks") }.buttonStyle(RowActionStyle())
            Button { route = .followUps } label: { ActionRow(title: "Your follow-ups") }.buttonStyle(RowActionStyle())
            Button { route = .snoozes } label: { ActionRow(title: "Hidden suggestions") }.buttonStyle(RowActionStyle())
        }.navigationTitle("Buddy Checks")
            .navigationDestination(item: $route) { route in
                switch route {
                case .search: ConnectedSearch(account: account)
                case .suggestion: ConnectedSuggestion(account: account)
                case .person(let id): ConnectedPerson(account: account, personID: id)
                case .draft: ConnectedCheckForm(account: account)
                case .history: ConnectedHistory(account: account)
                case .followUps: ConnectedFollowUps(account: account)
                case .snoozes: ConnectedSnoozes(account: account)
                }
            }
            .navigationDestination(isPresented: $reviewingCorrection) {
                ConnectedCorrectionReview(account: account) { _ in
                    reviewingCorrection = false; route = .draft
                }
            }
            .navigationDestination(isPresented: $showingReminder) {
                if let reminderDestination {
                    ConnectedFollowUpDetail(account: account, initial: reminderDestination.record,
                                            reminderChanged: reminderDestination.changed)
                }
            }
            .task {
                // Resolve the tapped UUID before reconciliation removes a closed
                // opt-in, so a stale alert can still explain the current status.
                await openReminder(); await account.reminders?.refresh()
            }
            .onChange(of: ReminderInbox.shared.link) { _, _ in Task { await openReminder() } }
            .onChange(of: ReminderInbox.shared.deliveryRevision) { _, _ in Task { await account.reminders?.refresh() } }
            .alert("Follow-up reminder", isPresented: Binding(get: { reminderError != nil }, set: { if !$0 { reminderError = nil } })) {
                Button("Retry") { Task { await openReminder() } }
                Button("Dismiss", role: .cancel) { ReminderInbox.shared.link = nil }
            } message: { Text(reminderError ?? "This reminder could not be opened.") }
            .alert("Couldn't finish that action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "Try again.") }
            .confirmationDialog("Discard the rejected submission?", isPresented: $discardRejected, titleVisibility: .visible) {
                Button("Discard rejected submission", role: .destructive) {
                    do { try account.journal?.discardRejectedSubmission() }
                    catch { self.error = safeMessage(error) }
                }
            } message: { Text("The Post rejected this request. Refresh the current record before entering a replacement.") }
    }
    private func openReminder() async {
        guard !readingReminder, let link = ReminderInbox.shared.link,
              link.namespace.hasPrefix("connected."), let reminders = account.reminders else { return }
        readingReminder = true; reminderError = nil; defer { readingReminder = false }
        do {
            let destination = try await reminders.resolve(namespace: link.namespace, reminder: link.reminder)
            guard ReminderInbox.shared.link == link, account.session != nil else { return }
            ReminderInbox.shared.link = nil
            route = nil; reminderDestination = destination; showingReminder = true
        } catch {
            guard account.session != nil, ReminderInbox.shared.link == link else { return }
            if case ClientError.server(404, _) = error {
                reminderError = "This follow-up reminder is no longer available from the Post."
            } else { reminderError = safeMessage(error) }
        }
    }
}

private struct ConnectedSearch: View {
    let account: ConnectedAccount
    @State private var query = ""
    @State private var committedQuery = ""
    @State private var people: [PersonIdentity] = []
    @State private var cursor: String?
    @State private var busy = false
    @State private var searched = false
    @State private var error: String?
    @State private var selected: Int?
    var body: some View {
        Page {
            SectionTitle("Who will you check on?")
            TextField("Search by first or last name", text: $query).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search by name").frame(minHeight: 48).submitLabel(.search)
                .onSubmit { Task { await search() } }
            Button(busy ? "Searching…" : "Search") { Task { await search() } }.buttonStyle(ActionStyle())
                .disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            if let error { Text(error) }
            if searched && people.isEmpty && error == nil { Text("No matching members. Try a first or last name.") }
            ForEach(people) { person in
                Button { selected = person.id } label: { ActionRow(title: person.name) }.buttonStyle(RowActionStyle())
            }
            if let cursor {
                Button("More results") { Task { await search(cursor: cursor) } }.buttonStyle(ActionStyle(primary: false)).disabled(busy)
            }
        }.navigationTitle("Member search")
            .navigationDestination(item: $selected) { ConnectedPerson(account: account, personID: $0) }
    }
    private func search(cursor: String? = nil) async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        if cursor == nil { people = []; self.cursor = nil; committedQuery = query; searched = false }
        do {
            let page = try await account.perform { client, token in try await client.people(query: committedQuery, cursor: cursor, token: token) }
            people += page.items.filter { item in !people.contains(where: { $0.id == item.id }) }
            self.cursor = page.nextCursor; searched = true
        } catch { self.error = safeMessage(error) }
    }
}

private struct ConnectedSuggestion: View {
    let account: ConnectedAccount
    @State private var suggestion: SuggestionResponse?
    @State private var skipped: [Int] = []
    @State private var selected: Int?
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        Page {
            if let suggestion, let person = suggestion.person, suggestion.state == .candidate {
                PersonCard(name: person.name)
                Text(suggestion.reason == "two_recorded_absences" ? "Recorded absent at the last two covered Post meetings." : "Their most recent recorded Buddy Check is older.")
                if let date = suggestion.reasonOn { Text("Record date: \(date)").font(.subheadline) }
                Button("Check on \(person.firstName)") { selected = person.id }.buttonStyle(ActionStyle()).disabled(busy)
                Button("Someone else") { skipped.append(person.id); Task { await load() } }.buttonStyle(ActionStyle(primary: false)).disabled(busy || skipped.count >= 50)

            } else if let suggestion {
                SectionTitle(suggestion.state == .insufficientHistory ? "More history is needed" : "No suggestion right now")
                Text(suggestion.state == .insufficientHistory ? "The Post has too little recorded history to suggest someone confidently." : "No eligible member is available with the current exclusions.")
                if suggestion.state == .insufficientHistory, let people = suggestion.randomCandidates, !people.isEmpty {
                    Text("A few people you could check on").font(.headline)
                    Text("Picked at random from eligible members.").font(.subheadline)
                    ForEach(people) { person in
                        Button { selected = person.id } label: { ActionRow(title: person.name) }
                            .buttonStyle(RowActionStyle()).disabled(busy)
                            .accessibilityLabel("Check on \(person.name)")
                    }
                }
                if !skipped.isEmpty {
                    Button("Include skipped members again") { skipped = []; Task { await load() } }.buttonStyle(ActionStyle(primary: false)).disabled(busy)
                }
            }
            if let error { Text(error) }
            if busy { ProgressView("Checking Post records") }
            if !busy { Button("Refresh suggestion") { Task { await load() } }.buttonStyle(ActionStyle(primary: false)) }
        }.navigationTitle("Suggested member").task { await load() }
            .navigationDestination(item: $selected) { ConnectedPerson(account: account, personID: $0) }
    }
    private func load() async {
        guard !busy else { return }; busy = true; error = nil; suggestion = nil; defer { busy = false }
        do { suggestion = try await account.perform { client, token in try await client.suggestion(excluding: skipped, token: token) } }
        catch { self.error = safeMessage(error) }
    }
}

private struct ConnectedPerson: View {
    let account: ConnectedAccount
    let personID: Int
    @Environment(\.openURL) private var openURL
    @State private var card: PersonCardResponse?
    @State private var error: String?
    @State private var showDraft = false
    @State private var busy = false
    var body: some View {
        Page {
            if let card {
                PersonCard(name: card.name)
                if !card.eligibility.eligible {
                    Text(eligibilityText(card.eligibility.reason))
                }
                if card.eligibility.eligible {
                    WorkingSurface {
                        SectionTitle("A way to start")
                        Text("“Hi \(card.firstName), I'm checking in from the Post. How have you been?”")
                    }
                }
                if let phone = card.phone {
                    Text(phone).textSelection(.enabled)
                    #if !targetEnvironment(simulator)
                    Button("Call \(card.firstName)") {
                        Task {
                            busy = true; defer { busy = false }
                            do {
                                let url = try await PhoneHandoff.prepare(personID: personID, account: account)
                                openURL(url) { accepted in
                                    if !accepted { error = "Phone could not open. Your unfinished check is retained." }
                                }
                            } catch { self.error = safeMessage(error) }
                        }
                    }.buttonStyle(ActionStyle()).disabled(busy || !card.eligibility.eligible)
                    #endif
                }
                Button("Record a check") { begin() }.buttonStyle(ActionStyle())
                    .disabled(busy || card.eligibility.reason == "contact_paused" || account.journal?.snapshot.pending != nil)
                if card.exportAvailable {
                    NavigationLink("Phone contact") { ConnectedContactsScreen(account: account, personID: personID) }
                        .buttonStyle(ActionStyle(primary: false))
                }
                Text("Record what actually happened. Opening a phone number does not mean you talked.").font(.footnote)
            }
            if let error { Text(error) }
            if busy { ProgressView("Checking member access") }
            if !busy { Button("Refresh member") { Task { await load() } }.buttonStyle(ActionStyle(primary: false)) }
        }.navigationTitle("Buddy Check").task { await load() }
            .navigationDestination(isPresented: $showDraft) { ConnectedCheckForm(account: account) }
    }
    private func begin() {
        do {
            guard let journal = account.journal else { throw ClientError.invalidInput }
            if let draft = journal.snapshot.draft {
                guard draft.personID == personID else { throw ClientError.unfinishedOperation }
            } else { try journal.saveDraft(ConnectedDraft(personID: personID)) }
            showDraft = true
        } catch { self.error = safeMessage(error) }
    }
    private func load() async {
        busy = true; card = nil; error = nil; defer { busy = false }
        do { card = try await account.perform { client, token in try await client.person(personID, token: token) } }
        catch ClientError.server(404, "not_found") { error = "This member is unavailable from the Post." }
        catch ClientError.connectionUnavailable { error = "The Post could not be reached. Refresh to check current member access." }
        catch ClientError.invalidResponse { error = "These member details could not be verified. Refresh to try again." }
        catch { self.error = safeMessage(error) }
    }
}

private struct ConnectedCheckForm: View {
    let account: ConnectedAccount
    @State private var draft: ConnectedDraft?
    @State private var card: PersonCardResponse?
    @State private var error: String?
    @State private var busy = false
    @State private var accepted = false
    @State private var discard = false
    @State private var reviewingCorrection = false
    @FocusState private var notesFocused: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Page {
            if let card { PersonCard(name: card.name) }
            if accepted {
                SectionTitle("Saved to the Post")
                Text("The Post confirmed your Buddy Check.")
                Button("Done") { dismiss() }.buttonStyle(ActionStyle())
            } else if let draft {
                WorkingSurface {
                    Text("How did you check in?").font(.headline)
                    Picker("Contact method", selection: binding(draft, \.channel)) {
                        Text("Phone").tag(CheckChannel.phone); Text("Text").tag(CheckChannel.text); Text("In person").tag(CheckChannel.inPerson)
                    }.pickerStyle(.menu)
                    Text("When did it happen?").font(.headline)
                    if let day = draft.correction?.legacyDate { Text(day + " · time not recorded") }
                    else {
                        DateTimeFields(selection: binding(draft, \.occurredAt), future: false)
                            .environment(\.timeZone, TimeZone(identifier: draft.entryZone) ?? .current)
                        Text(timeZoneText(draft.entryZone)).font(.footnote)
                    }
                }.disabled(busy || account.journal?.snapshot.pending != nil)
                WorkingSurface {
                    Text("What happened?").font(.headline)
                    ForEach(CheckResult.allCases, id: \.self) { outcome in
                        Button {
                            var next = draft; next.outcome = outcome; saveDraft(next)
                        } label: { Label(outcomeText(outcome.rawValue), systemImage: draft.outcome == outcome ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity, alignment: .leading) }
                            .buttonStyle(ActionStyle(primary: draft.outcome == outcome))
                            .accessibilityAddTraits(draft.outcome == outcome ? .isSelected : [])
                    }
                    TextField("Your check notes (optional)", text: binding(draft, \.notes), axis: .vertical).lineLimit(3...8)
                        .accessibilityLabel("Your check notes")
                        .focused($notesFocused)
                }
                .disabled(busy || account.journal?.snapshot.pending != nil)
                if draft.correction == nil { WorkingSurface {
                    Toggle("Set a follow-up", isOn: Binding(get: { draft.followUp != nil }, set: { on in
                        var next = draft
                        next.followUp = on ? try? FollowUpTime(dueAt: Date().addingTimeInterval(86400), entryZone: TimeZone.current.identifier) : nil
                        saveDraft(next)
                    }))
                    if let followUp = draft.followUp {
                        DateTimeFields(selection: Binding(get: { followUp.dueAt }, set: { value in
                            var next = draft; next.followUp = try? FollowUpTime(dueAt: value, entryZone: followUp.entryZone); saveDraft(next)
                        }), future: true).environment(\.timeZone, TimeZone(identifier: followUp.entryZone) ?? .current)
                        Text(timeZoneText(followUp.entryZone)).font(.footnote)
                        Text("This adds a follow-up to your Post account. Phone alerts are not enabled.").font(.footnote)
                    }
                }.disabled(busy || account.journal?.snapshot.pending != nil) }
                Button(busy ? "Saving…" : (draft.correction == nil ? "Save to Post" : "Save correction")) { Task { await submit() } }.buttonStyle(ActionStyle())
                    .disabled(busy || draft.outcome == nil || card == nil || account.journal?.snapshot.pending != nil)
                if account.journal?.snapshot.pending != nil {
                    if account.journal?.canReviewStaleCorrection == true {
                        SectionTitle("This check changed at the Post")
                        Text("Your correction was not saved. Review the current check before continuing with your changes.")
                        Button("Review latest check") { reviewingCorrection = true }.buttonStyle(ActionStyle())
                    } else {
                    Text(account.journal?.rejection == nil
                         ? "Submission pending. It may already have been accepted by the Post."
                         : "The Post rejected this submission. Your proposed changes are still on this iPhone.")
                    Button("Check submission") { Task {
                        guard let journal = account.journal else { return }
                        busy = true; defer { busy = false }
                        do {
                            _ = try await account.perform { client, token in try await journal.reconcile(client: client, token: token) }
                            accepted = true; error = nil
                        } catch { self.error = safeMessage(error) }
                    } }.buttonStyle(ActionStyle()).disabled(busy)
                    }
                } else {
                    Button("Discard unfinished check", role: .destructive) { discard = true }.frame(minHeight: 48).foregroundStyle(Palette.red)
                }
            }
            if let error { Text(error) }
        }.navigationTitle(draft?.correction == nil ? "Record a check" : "Correct check")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { notesFocused = false }.tint(Palette.action)
                }
            }
            .navigationDestination(isPresented: $reviewingCorrection) {
                ConnectedCorrectionReview(account: account) { replacement in
                    draft = replacement; error = nil; reviewingCorrection = false
                }
            }
            .task {
                draft = account.journal?.snapshot.draft
                if let draft {
                    do { card = try await account.perform { client, token in try await client.person(draft.personID, token: token) } }
                    catch { self.error = safeMessage(error) }
                }
            }
            .confirmationDialog("Discard this unfinished check?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard check", role: .destructive) {
                    do { try account.journal?.discardDraft(); dismiss() }
                    catch { self.error = safeMessage(error) }
                }
            }
    }
    private func binding<T>(_ source: ConnectedDraft, _ key: WritableKeyPath<ConnectedDraft, T>) -> Binding<T> {
        Binding(get: { (draft ?? source)[keyPath: key] }, set: { value in
            var next = draft ?? source; next[keyPath: key] = value; saveDraft(next)
        })
    }
    private func saveDraft(_ next: ConnectedDraft) {
        do { guard let journal = account.journal else { throw ClientError.invalidInput }; try journal.saveDraft(next); draft = next; error = nil }
        catch { self.error = safeMessage(error) }
    }
    private func submit() async {
        guard let draft, let journal = account.journal else { return }
        notesFocused = false
        busy = true; error = nil; defer { busy = false }
        do {
            try journal.prepare(draft.mutation())
            _ = try await account.perform { client, token in try await journal.reconcile(client: client, token: token) }
            accepted = true
        } catch { self.error = safeMessage(error) }
    }
}

private struct ConnectedHistory: View {
    let account: ConnectedAccount
    @State private var records: [ContactRecord] = []
    @State private var cursor: String?
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Page {
            if loaded && records.isEmpty { Text("You haven't recorded a Buddy Check here yet.") }
            ForEach(records) { record in
                ConnectedHistoryRow(account: account, record: record)
            }
            if let error { Text(error) }
            Button(busy ? "Loading…" : (cursor == nil ? "Refresh history" : "More checks")) { Task { await load(cursor: cursor) } }
                .buttonStyle(ActionStyle(primary: false)).disabled(busy)
        }.navigationTitle("Your checks").task { await load() }
    }
    private func load(cursor: String? = nil) async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do {
            let page = try await account.perform { client, token in try await client.history(cursor: cursor, token: token) }
            if cursor == nil { records = [] }
            // A corrected logical contact can appear again at a later source ID.
            for record in page.items {
                if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
                else { records.append(record) }
            }
            self.cursor = page.nextCursor; loaded = true
        } catch { self.error = safeMessage(error) }
    }
}

private struct ConnectedFollowUps: View {
    let account: ConnectedAccount
    @State private var records: [FollowUpRecord] = []
    @State private var cursor: String?
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        Page {
            if loaded && records.isEmpty { Text("You have no recorded follow-ups.") }
            ForEach(records) { record in
                ConnectedFollowUpRow(account: account, record: record)
            }
            if let error { Text(error) }
            Button(busy ? "Loading…" : (cursor == nil ? "Refresh follow-ups" : "More follow-ups")) { Task { await load(cursor: cursor) } }
                .buttonStyle(ActionStyle(primary: false)).disabled(busy)
        }.navigationTitle("Your follow-ups").task { await load() }
    }
    private func load(cursor: String? = nil) async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do {
            let page = try await account.perform { client, token in try await client.followUps(cursor: cursor, token: token) }
            if cursor == nil { records = [] }
            for record in page.items {
                if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
                else { records.append(record) }
            }
            self.cursor = page.nextCursor; loaded = true
        } catch { self.error = safeMessage(error) }
    }
}

private struct ConnectedSnoozes: View {
    let account: ConnectedAccount
    @State private var records: [SnoozeRecord] = []
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        Page {
            if loaded && records.isEmpty { Text("You have no hidden suggestions.") }
            ForEach(records) { record in
                ConnectedSnoozeRow(account: account, record: record) { await load() }
            }
            if let error { Text(error) }
            Button(busy ? "Loading…" : "Refresh hidden suggestions") { Task { await load() } }
                .buttonStyle(ActionStyle(primary: false)).disabled(busy)
        }.navigationTitle("Hidden suggestions").task { await load() }
    }
    private func load() async {
        guard !busy else { return }; busy = true; error = nil; loaded = false; defer { busy = false }
        do {
            var cursor: String?; var seen = Set<String>(); var active: [SnoozeRecord] = []
            repeat {
                let page = try await account.perform { client, token in try await client.snoozes(cursor: cursor, token: token) }
                active += page.items.filter { $0.cancelledAt == nil && $0.untilAt > Date() }
                cursor = page.nextCursor
                if let cursor, !seen.insert(cursor).inserted { throw ClientError.invalidResponse }
            } while cursor != nil
            records = active; loaded = true
        } catch { records = []; self.error = safeMessage(error) }
    }
}

private struct ConnectedSnoozeRow: View {
    let account: ConnectedAccount
    let record: SnoozeRecord
    let refresh: () async -> Void
    @State private var name = "Loading member…"
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        WorkingSurface {
            Text(name).font(.title2.bold())
            Text("Hidden from suggestions until \(dateText(record.untilAt))")
            Button("Show again") { Task {
                busy = true; defer { busy = false }
                do {
                    guard let journal = account.journal else { throw ClientError.journalUnavailable }
                    try journal.prepare(.undo(record))
                    _ = try await account.perform { client, token in try await journal.reconcile(client: client, token: token) }
                    await refresh()
                } catch { self.error = safeMessage(error) }
            } }.buttonStyle(ActionStyle(primary: false)).disabled(busy || account.journal?.snapshot.pending != nil)
            if let error { Text(error) }
        }.task {
            do { name = try await account.perform { client, token in try await client.person(record.personId, token: token).name } }
            catch { name = "Member unavailable" }
        }
    }
}

private struct ConnectedHistoryRow: View {
    let account: ConnectedAccount
    let record: ContactRecord
    @State private var name = "Loading member…"
    var body: some View {
        NavigationLink { ConnectedRecordDetail(account: account, initial: record) } label: {
            ActionRow(title: name, subtitle: outcomeText(record.outcome) + " · " + (record.occurredAt.map(dateText) ?? record.occurredOn))
        }.buttonStyle(RowActionStyle()).task {
            do { name = try await account.perform { client, token in try await client.person(record.personId, token: token).name } }
            catch { name = "Member unavailable" }
        }
    }
}

private struct ConnectedRecordDetail: View {
    let account: ConnectedAccount
    let initial: ContactRecord
    @State private var record: ContactRecord?
    @State private var name: String?
    @State private var busy = false
    @State private var error: String?
    @State private var correcting = false
    var body: some View {
        Page {
            if let name { PersonCard(name: name) }
            if let record {
                WorkingSurface {
                    SectionTitle(outcomeText(record.outcome))
                    Text(record.occurredAt.map(dateText) ?? (record.occurredOn + " · time not recorded"))
                    if let notes = record.notes, !notes.isEmpty { Text(notes) }
                }
                Button("Correct this check") {
                    do {
                        guard let journal = account.journal else { throw ClientError.journalUnavailable }
                        try journal.saveDraft(ConnectedDraft(correcting: record)); correcting = true
                    } catch { self.error = safeMessage(error) }
                }.buttonStyle(ActionStyle()).disabled(busy || account.journal?.snapshot.pending != nil)
            }
            if let error { Text(error) }
            Button(busy ? "Loading…" : "Refresh check") { Task { await load() } }.buttonStyle(ActionStyle(primary: false)).disabled(busy)
        }.navigationTitle("Recorded check").task { await load() }
            .navigationDestination(isPresented: $correcting) { ConnectedCheckForm(account: account) }
    }
    private func load() async {
        busy = true; error = nil; record = nil; name = nil; defer { busy = false }
        do {
            name = try await account.perform { client, token in try await client.person(initial.personId, token: token).name }
            var cursor: String?
            var seen = Set<String>()
            var latest: ContactRecord?
            repeat {
                let page = try await account.perform { client, token in try await client.revisions(contactID: initial.id, cursor: cursor, token: token) }
                for candidate in page.items where candidate.id == initial.id {
                    if candidate.revision > (latest?.revision ?? 0) { latest = candidate }
                }
                cursor = page.nextCursor
                if let cursor, !seen.insert(cursor).inserted { throw ClientError.invalidResponse }
            } while cursor != nil
            guard let latest else { throw ClientError.invalidResponse }
            record = latest
        } catch { self.error = safeMessage(error) }
    }
}

private struct ConnectedFollowUpRow: View {
    let account: ConnectedAccount
    let record: FollowUpRecord
    @State private var name = "Loading member…"
    var body: some View {
        NavigationLink { ConnectedFollowUpDetail(account: account, initial: record) } label: {
            ActionRow(title: name, subtitle: dateText(record.dueAt) + " · " + record.status.rawValue.capitalized)
        }.buttonStyle(RowActionStyle()).task {
            do { name = try await account.perform { client, token in try await client.person(record.personId, token: token).name } }
            catch { name = "Member unavailable" }
        }
    }
}

private struct ConnectedFollowUpDetail: View {
    let account: ConnectedAccount
    let initial: FollowUpRecord
    var reminderChanged = false
    @State private var name: String?
    @State private var updated: FollowUpRecord?
    @State private var reference: FollowUpRecord?
    @State private var due = Date().addingTimeInterval(86400)
    @State private var rescheduling = false
    @State private var cancelling = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Page {
            if let name { PersonCard(name: name) }
            if let record = updated {
                if reminderChanged {
                    Text("This follow-up changed after the reminder was scheduled. Its current details are shown.")
                }
                Text(dateText(record.dueAt)).font(.title2.bold())
                Text(record.status.rawValue.capitalized)
                if record.status == .open {
                    if let reminders = account.reminders {
                        ConnectedReminderControls(record: record, reminders: reminders)
                    }
                    NavigationLink("Open member") { ConnectedPerson(account: account, personID: record.personId) }.buttonStyle(ActionStyle())
                    Button("Mark follow-up complete") { Task { await change(.complete) } }.buttonStyle(ActionStyle(primary: false))
                        .disabled(busy || account.journal?.snapshot.pending != nil)
                    if rescheduling {
                        DateTimeFields(selection: $due, future: true).environment(\.timeZone, TimeZone(identifier: record.entryZone) ?? .current)
                        Text(timeZoneText(record.entryZone)).font(.footnote)
                        Button("Save new follow-up time") { Task {
                            do { await change(.reschedule(try FollowUpTime(dueAt: due, entryZone: record.entryZone))) }
                            catch { self.error = safeMessage(error) }
                        } }.buttonStyle(ActionStyle()).disabled(busy || account.journal?.snapshot.pending != nil)
                    } else {
                        Button("Reschedule") { due = max(record.dueAt, Date().addingTimeInterval(3600)); rescheduling = true }
                            .buttonStyle(ActionStyle(primary: false)).disabled(busy || account.journal?.snapshot.pending != nil)
                    }
                    Button("Cancel follow-up", role: .destructive) { cancelling = true }.foregroundStyle(Palette.red).frame(minHeight: 48)
                        .disabled(busy || account.journal?.snapshot.pending != nil)
                    Text("Completing a follow-up does not record a Buddy Check. Record what happened separately.").font(.footnote)
                }
            }
            if let error { Text(error) }
            Button(busy ? "Loading…" : "Refresh follow-up") { Task { await load() } }
                .buttonStyle(ActionStyle(primary: false)).disabled(busy)
        }.navigationTitle("Follow-up")
            .task { await load() }
            .confirmationDialog("Cancel this follow-up?", isPresented: $cancelling, titleVisibility: .visible) {
                Button("Cancel follow-up", role: .destructive) { Task { await change(.cancel) } }
            }
    }
    private func load() async {
        guard !busy else { return }
        let previous = reference ?? initial
        busy = true; error = nil; updated = nil; name = nil; rescheduling = false
        defer { busy = false }
        do {
            let current = try await account.perform { client, token in try await client.currentFollowUp(previous, token: token) }
            let person = try await account.perform { client, token in try await client.person(current.personId, token: token) }
            reference = current; updated = current; name = person.name
        } catch ClientError.server(404, "not_found") {
            error = "This follow-up is no longer available from the Post."
        } catch ClientError.connectionUnavailable {
            error = "The Post could not be reached. Refresh this follow-up to try again."
        } catch { self.error = safeMessage(error) }
        // A missing record or withdrawn permission must also reconcile its
        // existing phone alert. The coordinator preserves intent on network loss.
        await account.reminders?.refresh()
    }
    private func change(_ action: PendingMutation.FollowUpAction) async {
        guard !busy, let record = updated else { return }; busy = true; error = nil; defer { busy = false }
        do {
            guard let journal = account.journal else { throw ClientError.journalUnavailable }
            try journal.prepare(.change(record, action: action))
            let receipt = try await account.perform { client, token in try await journal.reconcile(client: client, token: token) }
            reference = receipt.followUp; updated = receipt.followUp; rescheduling = false
            await account.reminders?.refresh()
        } catch { self.error = safeMessage(error) }
    }
}

func outcomeText(_ value: String) -> String {
    switch value {
    case "reached": "We connected"
    case "no_answer": "No answer"
    case "message_left": "I left a message"
    case "wrong_number": "Wrong number"
    case "not_attempted": "No contact attempted"
    case "callback_requested": "Callback requested"
    default: "Recorded check"
    }
}
private func eligibilityText(_ reason: String?) -> String {
    switch reason {
    case "contact_paused": "Contact with this member is paused."
    case "assigned_elsewhere": "Another caller has an active assignment for this member."
    case "open_follow_up": "A follow-up is already arranged."
    case "recent_attempt": "A recent contact attempt is recorded."
    case "recent_conversation": "A recent conversation is recorded."
    default: "New outreach is unavailable right now."
    }
}

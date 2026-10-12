import SwiftUI
import BuddyCheckAPI

private enum ConnectedRoute: Hashable { case search, suggestion, draft }

struct ConnectedMainView: View {
    let account: ConnectedAccount
    let session: MobileSession
    let openSettings: () -> Void
    @State private var navigation = ConnectedNavigation()
    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.tab) {
            NavigationStack {
                ConnectedHome(account: account, session: session, openSettings: openSettings)
            }.id(navigation.homeIdentity).tabItem { Label("Home", systemImage: "house") }.tag(0)
            NavigationStack {
                ConnectedFollowUps(account: account).toolbar { settingsButton }
            }.id(navigation.followUpsIdentity).tabItem { Label("Follow-ups", systemImage: "calendar") }.tag(1)
        }
        .environment(navigation)
        .onChange(of: ReminderInbox.shared.link) { _, link in
            if link?.namespace.hasPrefix("connected.") == true { navigation.tab = 0 }
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
    let openSettings: () -> Void
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
        Page(spacing: 0, topPadding: 0, decorated: true) {
            BuddyMasthead(post: session.installation.name, openSettings: openSettings)
            if let journal = account.journal {
                if journal.snapshot.pending != nil {
                    SectionBand(color: Palette.context) {
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
                } else if let draft = journal.snapshot.draft {
                    ConnectedDraftAction(account: account, draft: draft) { route = .draft }
                }
            }
            ConnectedHomeActivity(account: account, showsNext: account.journal?.snapshot.draft == nil && account.journal?.snapshot.pending == nil) { route = .search }
        }.navigationTitle("Buddy Checks")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $route) { route in
                switch route {
                case .search: ConnectedSearch(account: account)
                case .suggestion: ConnectedSuggestion(account: account)
                case .draft: ConnectedCheckForm(account: account)
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
        Page(spacing: 0, topPadding: 0) {
            SectionBand(color: Palette.context) {
                Text("Who’s on your mind?").font(.title.bold())
                TextField("First or last name", text: $query).textFieldStyle(.plain)
                    .padding(13).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Search by name").submitLabel(.search)
                    .onSubmit { Task { await search() } }
                Button(busy ? "Searching…" : "Search") { Task { await search() } }.buttonStyle(ActionStyle(primary: false))
                    .disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            }
            if searched || error != nil {
                SectionBand {
                    SectionTitle("Search results")
                    if let error { Text(error) }
                    if searched && people.isEmpty && error == nil { Text("No matching members. Try a first or last name.") }
                    ForEach(people) { person in
                        Button { selected = person.id } label: {
                            HStack(spacing: 12) { PersonAvatar(name: person.name, size: 42); ActionRow(title: person.name) }
                        }.buttonStyle(RowActionStyle())
                    }
                    if let cursor {
                        Button("More results") { Task { await search(cursor: cursor) } }.buttonStyle(ActionStyle(primary: false)).disabled(busy)
                    }
                    Button("Browse suggestions") { searched = false; error = nil; query = "" }.buttonStyle(ActionStyle(primary: false))
                }
            } else {
                ConnectedSuggestion(account: account, embedded: true)
            }
        }.navigationTitle("Choose a member")
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
    var embedded = false
    @State private var suggestion: SuggestionResponse?
    @State private var skipped: [Int] = []
    @State private var selected: Int?
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        Group {
            if embedded { content }
            else { Page(spacing: 0, topPadding: 0) { content } }
        }.navigationTitle(embedded ? "Choose a member" : "Suggested member").task { await load() }
            .navigationDestination(item: $selected) { ConnectedPerson(account: account, personID: $0) }
    }
    private var content: some View {
        SectionBand(color: Palette.paper.opacity(0.5), spacing: 12) {
            Label("Suggested by the Post", systemImage: "star").font(.title3.bold())
            if let suggestion, let person = suggestion.person, suggestion.state == .candidate {
                Button { selected = person.id } label: {
                    HStack(spacing: 12) {
                        PersonAvatar(name: person.name, size: 42)
                        ActionRow(title: person.name, subtitle: suggestion.reason == "two_recorded_absences" ? "Recorded absent at the last two covered Post meetings." : "Their most recent recorded Buddy Check is older.")
                    }
                }.buttonStyle(RowActionStyle()).disabled(busy)
                if let date = suggestion.reasonOn { Text("Record date: \(date)").font(.footnote).foregroundStyle(.secondary) }
                Button("Someone else") { skipped.append(person.id); Task { await load() } }.buttonStyle(ActionStyle(primary: false)).disabled(busy || skipped.count >= 50)
            } else if let suggestion {
                Text(suggestion.state == .insufficientHistory ? "More history is needed" : "No suggestion right now").font(.headline)
                Text(suggestion.state == .insufficientHistory ? "The Post has too little recorded history to suggest someone confidently." : "No eligible member is available with the current exclusions.").font(.subheadline)
                if suggestion.state == .insufficientHistory, let people = suggestion.randomCandidates, !people.isEmpty {
                    Text("Picked at random from eligible members.").font(.subheadline)
                    ForEach(people) { person in
                        Button { selected = person.id } label: {
                            HStack(spacing: 12) { PersonAvatar(name: person.name, size: 42); ActionRow(title: person.name) }
                        }.buttonStyle(RowActionStyle()).disabled(busy)
                            .accessibilityLabel("Check on \(person.name)")
                    }
                }
                if !skipped.isEmpty {
                    Button("Include skipped members again") { skipped = []; Task { await load() } }.buttonStyle(ActionStyle(primary: false)).disabled(busy)
                }
            }
            if let error { Text(error) }
            if busy { ProgressView("Checking Post records") }
            NavigationLink { ConnectedSnoozes(account: account) } label: { ActionRow(title: "Hidden suggestions") }.buttonStyle(RowActionStyle())
            if error != nil && !busy { Button("Refresh suggestion") { Task { await load() } }.buttonStyle(ActionStyle(primary: false)) }
        }
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
        Page(spacing: 0, topPadding: 0) {
            if let card {
                MemberProfile(name: card.name, subtitle: account.session?.installation.name ?? "")
                SectionBand {
                    if !card.eligibility.eligible { Text(eligibilityText(card.eligibility.reason)) }
                    if card.phone != nil {
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
                    Button("Record a check") { begin() }.buttonStyle(ActionStyle(primary: card.phone == nil))
                        .disabled(busy || card.eligibility.reason == "contact_paused" || account.journal?.snapshot.pending != nil)
                    if let phone = card.phone {
                        HStack { Text(phone).textSelection(.enabled); Spacer(); Text("Phone").font(.subheadline).foregroundStyle(.secondary) }
                            .padding(.top, 10)
                    }
                }
                if card.eligibility.eligible { ConversationPrompt(firstName: card.firstName) }
                if card.exportAvailable {
                    NavigationLink { ConnectedContactsScreen(account: account, personID: personID) } label: {
                        ActionRow(title: "Phone contact", subtitle: "Add or review contact details")
                    }.buttonStyle(RowActionStyle())
                }
            }
            if let error { Text(error).padding(.vertical, 16) }
            if busy { ProgressView("Checking member access").padding(.vertical, 16) }
            if !busy { Button("Refresh member", systemImage: "arrow.clockwise") { Task { await load() } }.frame(minHeight: 48) }
        }.navigationTitle("Buddy Check").task { await load() }
            .toolbarBackground(Palette.navy, for: .navigationBar).toolbarColorScheme(.dark, for: .navigationBar)
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

struct ConnectedHistory: View {
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

struct ConnectedRecordDetail: View {
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
            record = try await account.perform { client, token in try await client.latestContact(initial, token: token) }
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

struct ConnectedFollowUpDetail: View {
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
        Page(spacing: 0, topPadding: 0) {
            if let record = updated {
                SectionBand(color: Palette.context) {
                    if let name { PersonCard(name: name) }
                    if reminderChanged { Text("This follow-up changed after the reminder was scheduled. Its current details are shown.") }
                    HStack(spacing: 14) {
                        CalendarStamp(date: record.dueAt, zone: record.entryZone)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(connectedDateText(record.dueAt, zone: record.entryZone)).font(.headline)
                            Text(record.status.rawValue.capitalized).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if record.status == .open && !rescheduling {
                            Button("Reschedule") { due = max(record.dueAt, Date().addingTimeInterval(3600)); rescheduling = true }
                                .buttonStyle(.bordered).buttonBorderShape(.capsule)
                                .disabled(busy || account.journal?.snapshot.pending != nil)
                        }
                    }
                    if record.status == .open {
                        if rescheduling {
                            DateTimeFields(selection: $due, future: true).environment(\.timeZone, TimeZone(identifier: record.entryZone) ?? .current)
                            Text(timeZoneText(record.entryZone)).font(.footnote)
                            Button("Save new follow-up time") { Task {
                                do { await change(.reschedule(try FollowUpTime(dueAt: due, entryZone: record.entryZone))) }
                                catch { self.error = safeMessage(error) }
                            } }.buttonStyle(ActionStyle()).disabled(busy || account.journal?.snapshot.pending != nil)
                        }
                        NavigationLink("Check on this member") { ConnectedPerson(account: account, personID: record.personId) }.buttonStyle(ActionStyle())
                    }
                }
                if record.status == .open {
                    if let reminders = account.reminders {
                        SectionBand { ConnectedReminderControls(record: record, reminders: reminders) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Mark follow-up complete") { Task { await change(.complete) } }.buttonStyle(ActionStyle(primary: false))
                            .disabled(busy || account.journal?.snapshot.pending != nil)
                        Text("Completing a follow-up does not record a Buddy Check. Record what happened separately.").font(.footnote).foregroundStyle(.secondary)
                        Button("Cancel follow-up", role: .destructive) { cancelling = true }.foregroundStyle(Palette.red).frame(minHeight: 48)
                            .disabled(busy || account.journal?.snapshot.pending != nil)
                    }.padding(.top, 22)
                }
            }
            if let error { Text(error).padding(.vertical, 16) }
            Button(busy ? "Loading…" : "Refresh follow-up") { Task { await load() } }
                .font(.subheadline).frame(minHeight: 48).disabled(busy)
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

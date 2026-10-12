import SwiftUI
import BuddyCheckAPI

@Observable @MainActor final class ConnectedNavigation {
    var tab = 0
    var homeIdentity = UUID()
    var followUpsIdentity = UUID()
    func returnHome() {
        tab = 0; homeIdentity = UUID(); followUpsIdentity = UUID()
    }
}

struct ConnectedCheckForm: View {
    let account: ConnectedAccount
    @State private var draft: ConnectedDraft?
    @State private var card: PersonCardResponse?
    @State private var receipt: MutationReceipt?
    @State private var error: String?
    @State private var busy = false
    @State private var discard = false
    @State private var reviewingCorrection = false
    @State private var editingDetails = false
    @State private var showingNotes = false
    @State private var editingFollowUp = false
    @FocusState private var notesFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectedNavigation.self) private var navigation

    private var pending: Bool { account.journal?.snapshot.pending != nil }
    var body: some View {
        Page(scrollResetID: receipt?.operationId.uuidString ?? (pending ? "pending" : draft?.id.uuidString), spacing: 16, topPadding: 16) {
            if let card { PersonCard(name: card.name) }
            if let receipt { confirmation(receipt) }
            else if let draft {
                if pending { recovery }
                details(draft).disabled(busy || pending)
                outcomes(draft).disabled(busy || pending)
                WorkingSurface {
                    DisclosureGroup(isExpanded: $showingNotes) {
                        TextField("Your check notes (optional)", text: binding(draft, \.notes), axis: .vertical)
                            .lineLimit(3...8).focused($notesFocused)
                    } label: { Text(draft.notes.isEmpty ? "Add a note" : "Note added").font(.body) }
                }.disabled(busy || pending)
                if draft.correction == nil { followUp(draft).disabled(busy || pending) }
                if !pending {
                    Button("Discard unfinished check", role: .destructive) { discard = true }
                        .frame(minHeight: 48).foregroundStyle(Palette.red).disabled(busy)
                }
            }
            if let error { Text(error).foregroundStyle(Palette.red) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if receipt == nil, let draft, !pending {
                HStack(spacing: 16) {
                    Button(busy ? "Saving…" : (draft.correction == nil ? "Save to Post" : "Save correction")) {
                        Task { await submit() }
                    }.buttonStyle(ActionStyle())
                        .disabled(busy || draft.outcome == nil || card == nil)
                    if notesFocused {
                        Button("Done") { notesFocused = false }
                            .font(.headline).foregroundStyle(Palette.action).frame(minWidth: 52, minHeight: 48)
                    }
                }.padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Palette.surface)
            }
        }
        .navigationTitle(receipt != nil ? "Check saved" : (draft?.correction == nil ? "Record a check" : "Correct check"))
        .scrollDismissesKeyboard(.interactively)
        .navigationDestination(isPresented: $reviewingCorrection) {
            ConnectedCorrectionReview(account: account) { replacement in
                draft = replacement; error = nil; reviewingCorrection = false
                showingNotes = !replacement.notes.isEmpty
            }
        }
        .task {
            // Returning from the saved follow-up must keep the accepted receipt.
            guard receipt == nil else { return }
            draft = account.journal?.snapshot.draft
            showingNotes = !(draft?.notes.isEmpty ?? true)
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

    private func details(_ draft: ConnectedDraft) -> some View {
        WorkingSurface {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(channelText(draft.channel.rawValue)).font(.headline)
                    Text(draft.correction?.legacyDate.map { $0 + " · time not recorded" }
                         ?? connectedDateText(draft.occurredAt, zone: draft.entryZone)).font(.subheadline)
                }
                Spacer()
                Button(editingDetails ? "Done" : "Edit") { editingDetails.toggle() }.frame(minHeight: 44).foregroundStyle(Palette.action)
            }
            if editingDetails {
                Picker("Contact method", selection: binding(draft, \.channel)) {
                    Text("Phone").tag(CheckChannel.phone)
                    Text("Text").tag(CheckChannel.text)
                    Text("In person").tag(CheckChannel.inPerson)
                }.pickerStyle(.segmented)
                if draft.correction?.legacyDate == nil {
                    DateTimeFields(selection: binding(draft, \.occurredAt), future: false)
                        .environment(\.timeZone, TimeZone(identifier: draft.entryZone) ?? .current)
                }
            }
        }
    }

    private func outcomes(_ draft: ConnectedDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What happened?").font(.headline)
            VStack(spacing: 0) {
                ForEach(CheckResult.allCases, id: \.self) { outcome in
                    if outcome != CheckResult.allCases.first { Divider().padding(.leading, 16) }
                    Button {
                        var next = draft; next.outcome = outcome; saveDraft(next)
                    } label: {
                        HStack {
                            Text(outcomeText(outcome.rawValue))
                            Spacer()
                            Image(systemName: draft.outcome == outcome ? "checkmark.circle.fill" : "circle")
                        }.font(.body).padding(.horizontal, 16).frame(minHeight: 48)
                            .foregroundStyle(draft.outcome == outcome ? Palette.actionInk : Palette.ink)
                            .background(draft.outcome == outcome ? Palette.actionSurface : Palette.surface)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func followUp(_ draft: ConnectedDraft) -> some View {
        WorkingSurface {
            Toggle("Set a follow-up", isOn: Binding(get: { draft.followUp != nil }, set: { on in
                var next = draft
                next.followUp = on ? try? FollowUpTime(dueAt: Date().addingTimeInterval(86400), entryZone: TimeZone.current.identifier) : nil
                saveDraft(next); editingFollowUp = false
            }))
            if let followUp = draft.followUp {
                HStack(alignment: .firstTextBaseline) {
                    Text(connectedDateText(followUp.dueAt, zone: followUp.entryZone)).font(.subheadline)
                    Spacer()
                    Button(editingFollowUp ? "Done" : "Change time") { editingFollowUp.toggle() }.frame(minHeight: 44).foregroundStyle(Palette.action)
                }
                if editingFollowUp {
                    DateTimeFields(selection: Binding(get: { followUp.dueAt }, set: { value in
                        var next = draft
                        next.followUp = try? FollowUpTime(dueAt: value, entryZone: followUp.entryZone)
                        saveDraft(next)
                    }), future: true).environment(\.timeZone, TimeZone(identifier: followUp.entryZone) ?? .current)
                }
                Text("Included when you save. Phone alerts stay off.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var recovery: some View {
        WorkingSurface {
            if account.journal?.canReviewStaleCorrection == true {
                SectionTitle("This check changed at the Post")
                Text("Your correction was not saved. Review the current check before continuing with your changes.")
                Button("Review latest check") { reviewingCorrection = true }.buttonStyle(ActionStyle())
            } else {
                Text(account.journal?.rejection == nil
                     ? "Submission pending. It may already have been accepted by the Post."
                     : "The Post rejected this submission. Your proposed changes are still on this iPhone.")
                Button("Check submission") { Task { await reconcile() } }.buttonStyle(ActionStyle()).disabled(busy)
            }
        }
    }

    private func confirmation(_ receipt: MutationReceipt) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkingSurface {
                Label("Saved to the Post", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Palette.navy)
                if let record = receipt.contact {
                    Text(outcomeText(record.outcome)).font(.title2.bold())
                    Text(channelText(record.channel) + " · " + contactTimeText(record)).font(.subheadline)
                }
                Text("The Post confirmed your Buddy Check.").font(.subheadline).foregroundStyle(.secondary)
            }
            if let followUp = receipt.followUp {
                WorkingSurface {
                    Text("Follow-up saved").font(.headline)
                    Text(connectedDateText(followUp.dueAt, zone: followUp.entryZone))
                    Text(account.reminders?.status(followUp.id).label ?? "Phone alert status unavailable.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink("View follow-up") {
                        ConnectedFollowUpDetail(account: account, initial: followUp)
                    }.buttonStyle(ActionStyle(primary: false))
                }
            }
            Button("Back to Home", action: navigation.returnHome).buttonStyle(ActionStyle())
            if let record = receipt.contact {
                Button("Correct this check") { Task { await correct(record) } }
                    .frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(Palette.action).disabled(busy || account.journal?.snapshot.draft != nil || pending)
            }
        }
    }

    private func correct(_ record: ContactRecord) async {
        busy = true; error = nil; defer { busy = false }
        do {
            let current = try await account.perform { client, token in try await client.latestContact(record, token: token) }
            guard let journal = account.journal else { throw ClientError.journalUnavailable }
            let replacement = try ConnectedDraft(correcting: current)
            try journal.saveDraft(replacement)
            draft = replacement; receipt = nil; editingDetails = false; showingNotes = !replacement.notes.isEmpty
        } catch { self.error = safeMessage(error) }
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
        do { try journal.prepare(draft.mutation()); await reconcile() }
        catch { self.error = safeMessage(error) }
    }
    private func reconcile() async {
        guard let journal = account.journal else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            receipt = try await account.perform { client, token in try await journal.reconcile(client: client, token: token) }
        } catch { self.error = safeMessage(error) }
    }
}

func channelText(_ channel: String) -> String {
    switch channel { case "phone": "Phone"; case "text": "Text"; case "in_person": "In person"; default: channel.replacingOccurrences(of: "_", with: " ").capitalized }
}
func connectedDateText(_ date: Date, zone: String) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium; formatter.timeStyle = .short
    formatter.timeZone = TimeZone(identifier: zone) ?? .current
    let suffix = formatter.timeZone.identifier == TimeZone.current.identifier ? "" : " · " + timeZoneText(zone)
    return formatter.string(from: date) + suffix
}
func contactTimeText(_ record: ContactRecord) -> String {
    record.occurredAt.map { connectedDateText($0, zone: record.entryZone ?? TimeZone.current.identifier) }
        ?? record.occurredOn + " · time not recorded"
}

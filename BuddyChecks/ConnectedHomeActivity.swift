import SwiftUI
import BuddyCheckAPI

struct ConnectedDraftAction: View {
    let account: ConnectedAccount
    let draft: ConnectedDraft
    let resume: () -> Void
    @State private var name: String?
    var body: some View {
        SectionBand(color: Palette.context) {
            Text(draft.correction == nil ? "Unfinished check" : "Unfinished correction").font(.subheadline)
            if let name { PersonCard(name: name) }
            Button(name.map { "Continue with " + ($0.split(separator: " ").first.map(String.init) ?? $0) } ?? "Continue unfinished check", action: resume)
                .buttonStyle(ActionStyle())
            Text("Your changes are on this iPhone.").font(.subheadline).foregroundStyle(.secondary)
        }.task(id: draft.personID) {
            name = nil
            name = try? await account.perform { client, token in try await client.person(draft.personID, token: token).name }
        }
    }
}

struct ConnectedHomeActivity: View {
    let account: ConnectedAccount
    var showsNext = true
    let choose: () -> Void
    @State private var next: FollowUpRecord?
    @State private var records: [ContactRecord] = []
    @State private var loadingNext = true
    @State private var loadingRecent = true
    @State private var nextError: String?
    @State private var recentError: String?
    @State private var refreshID = UUID()
    private var revision: String { refreshID.uuidString + (account.journal?.lastReceipt?.operationId.uuidString ?? "") }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsNext {
                SectionBand(color: Palette.context) {
                    if loadingNext || loadingRecent { ProgressView("Loading your activity") }
                    else if nextError != nil || recentError != nil {
                        PageInvitation(title: "Activity unavailable", detail: "Your activity could not be fully checked. Refresh to try again.", symbol: "exclamationmark")
                    } else if let next {
                        Text("Next follow-up").font(.subheadline).foregroundStyle(.secondary)
                        NextFollowUp(account: account, record: next).id(refreshID)
                    } else {
                        PageInvitation(title: records.isEmpty ? "Your first Buddy Check" : "Who will you check on?",
                                       detail: "Find someone by name, or let the Post suggest a person.")
                    }
                    Button("Choose a member", action: choose).buttonStyle(ActionStyle(primary: next == nil))
                }
            }
            SectionBand(spacing: 10) {
                HStack {
                    SectionTitle("Recent checks")
                    Spacer()
                    NavigationLink("Your checks") { ConnectedHistory(account: account) }
                        .font(.subheadline).buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
                if loadingRecent { ProgressView("Loading recent checks") }
                else if let recentError { Text(recentError).font(.subheadline) }
                else if records.isEmpty { Text("Your recorded checks will appear here.").foregroundStyle(.secondary) }
                else {
                    VStack(spacing: 0) {
                        ForEach(records) { record in
                            HomeActivityRow(account: account, personID: record.personId,
                                            detail: outcomeText(record.outcome) + " · " + contactTimeText(record)) {
                                ConnectedRecordDetail(account: account, initial: record)
                            }.id(String(record.id) + refreshID.uuidString)
                        }
                    }
                }
                if !showsNext, let nextError { Text(nextError).font(.subheadline) }
            }
            Button("Refresh activity", systemImage: "arrow.clockwise") { refreshID = UUID() }
                .font(.subheadline).frame(minHeight: 48).disabled(loadingNext || loadingRecent)
        }
        .task(id: revision) { await loadNext() }
        .task(id: revision) { await loadRecent() }
    }
    private func loadNext() async {
        loadingNext = true; next = nil; nextError = nil
        defer { if !Task.isCancelled { loadingNext = false } }
        do {
            let result = try await account.perform { client, token in try await client.nextOpenFollowUp(token: token) }
            try Task.checkCancellation(); next = result
        }
        catch is CancellationError { }
        catch { nextError = "Follow-ups could not be loaded. Refresh to try again." }
    }
    private func loadRecent() async {
        loadingRecent = true; records = []; recentError = nil
        defer { if !Task.isCancelled { loadingRecent = false } }
        do {
            let result = try await account.perform { client, token in try await client.recentChecks(token: token) }
            try Task.checkCancellation(); records = result
        }
        catch is CancellationError { }
        catch { recentError = "Recent checks could not be loaded. Refresh to try again." }
    }
}

private struct NextFollowUp: View {
    let account: ConnectedAccount
    let record: FollowUpRecord
    @State private var name: String?
    @State private var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let name {
                HStack(spacing: 14) {
                    PersonAvatar(name: name, gold: true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(name).font(.title2.bold())
                        Text(connectedDateText(record.dueAt, zone: record.entryZone)).font(.subheadline)
                            .padding(.horizontal, 7).padding(.vertical, 3).background(Palette.paper, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                NavigationLink("Open follow-up") { ConnectedFollowUpDetail(account: account, initial: record) }.buttonStyle(ActionStyle())
            } else { Text(failed ? "Member details unavailable. Refresh activity to try again." : "Loading member…") }
        }.task(id: record.personId) {
            name = nil; failed = false
            do { name = try await account.perform { client, token in try await client.person(record.personId, token: token).name } }
            catch { failed = true }
        }
    }
}

private struct HomeActivityRow<Destination: View>: View {
    let account: ConnectedAccount
    let personID: Int
    let detail: String
    @ViewBuilder let destination: () -> Destination
    @State private var name: String?
    @State private var failed = false
    var body: some View {
        Group {
            if let name {
                NavigationLink(destination: destination) {
                    HStack(spacing: 12) {
                        PersonAvatar(name: name, size: 41)
                        ActionRow(title: name, subtitle: detail)
                    }
                }.buttonStyle(RowActionStyle()).accessibilityLabel(name + ", " + detail)
            } else {
                Text(failed ? "Member details unavailable. Refresh activity to try again." : "Loading member…")
                    .font(.subheadline).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.task(id: personID) {
            name = nil; failed = false
            do { name = try await account.perform { client, token in try await client.person(personID, token: token).name } }
            catch { failed = true }
        }
    }
}

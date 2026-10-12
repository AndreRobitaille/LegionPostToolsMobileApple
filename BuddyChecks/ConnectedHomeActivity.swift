import SwiftUI
import BuddyCheckAPI

struct ConnectedDraftAction: View {
    let account: ConnectedAccount
    let draft: ConnectedDraft
    let resume: () -> Void
    @State private var name: String?
    var body: some View {
        WorkingSurface {
            Text(draft.correction == nil ? "Unfinished check" : "Unfinished correction").font(.subheadline)
            Button(name.map { "Continue with " + $0 } ?? "Continue unfinished check", action: resume)
                .buttonStyle(ActionStyle())
        }.task(id: draft.personID) {
            name = nil
            name = try? await account.perform { client, token in try await client.person(draft.personID, token: token).firstName }
        }
    }
}

struct ConnectedHomeActivity: View {
    let account: ConnectedAccount
    @State private var next: FollowUpRecord?
    @State private var records: [ContactRecord] = []
    @State private var loadingNext = true
    @State private var loadingRecent = true
    @State private var nextError: String?
    @State private var recentError: String?
    @State private var refreshID = UUID()
    private var revision: String { refreshID.uuidString + (account.journal?.lastReceipt?.operationId.uuidString ?? "") }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Up next")
                if loadingNext { ProgressView("Loading follow-ups") }
                else if let nextError { Text(nextError).font(.subheadline) }
                else if let next {
                    HomeActivityRow(account: account, personID: next.personId,
                                    detail: connectedDateText(next.dueAt, zone: next.entryZone)) {
                        ConnectedFollowUpDetail(account: account, initial: next)
                    }
                } else { Text("No open follow-ups.").foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Recent checks")
                    Spacer()
                    NavigationLink("Your checks") { ConnectedHistory(account: account) }.font(.subheadline).frame(minHeight: 44).foregroundStyle(Palette.action)
                }
                if loadingRecent { ProgressView("Loading recent checks") }
                else if let recentError { Text(recentError).font(.subheadline) }
                else if records.isEmpty { Text("Your recorded checks will appear here.").foregroundStyle(.secondary) }
                else {
                    VStack(spacing: 0) {
                        ForEach(records) { record in
                            if record.id != records.first?.id { Divider().padding(.horizontal, 16) }
                            HomeActivityRow(account: account, personID: record.personId,
                                            detail: outcomeText(record.outcome) + " · " + contactTimeText(record)) {
                                ConnectedRecordDetail(account: account, initial: record)
                            }
                        }
                    }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            Button("Refresh activity", systemImage: "arrow.clockwise") { refreshID = UUID() }
                .font(.subheadline).frame(minHeight: 44).foregroundStyle(Palette.action).disabled(loadingNext || loadingRecent)
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
                        VStack(alignment: .leading, spacing: 5) {
                            Text(name).font(.headline).foregroundStyle(Palette.actionInk)
                            Text(detail).font(.subheadline).foregroundStyle(Palette.ink)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(Palette.action)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            } else {
                Text(failed ? "Member details unavailable. Refresh activity to try again." : "Loading member…")
                    .font(.subheadline).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .task(id: personID) {
                name = nil; failed = false
                do { name = try await account.perform { client, token in try await client.person(personID, token: token).name } }
                catch { failed = true }
            }
    }
}

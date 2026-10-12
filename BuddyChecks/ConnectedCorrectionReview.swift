import SwiftUI
import BuddyCheckAPI

/// Server facts are transient. Only the caller's own proposed facts enter the journal.
struct ConnectedCorrectionReview: View {
    let account: ConnectedAccount
    let continueEditing: (ConnectedDraft) -> Void
    @State private var current: ContactRecord?
    @State private var name: String?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Page {
            if let name { PersonCard(name: name) }
            if let current, let draft = account.journal?.snapshot.draft {
                WorkingSurface {
                    SectionTitle("Current Post record")
                    facts(channel: current.channel, outcome: current.outcome,
                          date: current.occurredAt, day: current.occurredOn,
                          zone: current.entryZone, notes: current.notes)
                }
                WorkingSurface {
                    SectionTitle("Your proposed correction")
                    facts(channel: draft.channel.rawValue, outcome: draft.outcome?.rawValue ?? "",
                          date: draft.correction?.legacyDate == nil ? draft.occurredAt : nil,
                          day: draft.correction?.legacyDate ?? "", zone: draft.entryZone, notes: draft.notes)
                }
                Text("Your changes stay editable. Nothing is sent until you save again.")
                Button("Continue with my correction") {
                    do {
                        guard let journal = account.journal else { throw ClientError.journalUnavailable }
                        let replacement = try journal.continueCorrection(afterReviewing: current)
                        continueEditing(replacement)
                    } catch { self.error = safeMessage(error) }
                }.buttonStyle(ActionStyle()).disabled(busy || account.journal?.canReviewStaleCorrection != true)
            }
            if let error { Text(error) }
            Button(busy ? "Loading…" : "Refresh current check") { Task { await load() } }
                .buttonStyle(ActionStyle(primary: false)).disabled(busy)
        }.navigationTitle("Review changes").task { await load() }
    }
    @ViewBuilder private func facts(channel: String, outcome: String, date: Date?, day: String, zone: String?, notes: String?) -> some View {
        Text(outcomeText(outcome)).font(.headline)
        Text(channel == "phone" ? "Phone" : channel == "text" ? "Text" : "In person")
        if let date {
            Text(date.formatted(.dateTime.day().month().year().hour().minute().timeZone().locale(Locale.current)))
            if let zone { Text("Entered in \(zone)").font(.footnote) }
        } else { Text(day + " · time not recorded") }
        Text(notes.flatMap { $0.isEmpty ? nil : $0 } ?? "No notes.")
    }
    private func load() async {
        busy = true; current = nil; name = nil; error = nil; defer { busy = false }
        do {
            guard let journal = account.journal, journal.canReviewStaleCorrection,
                  let draft = journal.snapshot.draft, let reference = draft.correction else { throw ClientError.unfinishedOperation }
            name = try await account.perform { client, token in try await client.person(draft.personID, token: token).name }
            var cursor: String?
            var seen = Set<String>()
            var latest: ContactRecord?
            repeat {
                let page = try await account.perform { client, token in
                    try await client.revisions(contactID: reference.contactID, cursor: cursor, token: token)
                }
                for record in page.items {
                    guard record.id == reference.contactID, record.personId == draft.personID else { throw ClientError.invalidResponse }
                    if record.revision > (latest?.revision ?? 0) { latest = record }
                }
                cursor = page.nextCursor
                if let cursor, !seen.insert(cursor).inserted { throw ClientError.invalidResponse }
            } while cursor != nil
            guard let latest, latest.revision > reference.expectedRevision else { throw ClientError.invalidResponse }
            current = latest
        } catch { self.error = safeMessage(error) }
    }
}

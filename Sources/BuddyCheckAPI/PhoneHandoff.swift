import Foundation

@MainActor public enum PhoneHandoff {
    public static func prepare(personID: Int, account: ConnectedAccount, now: () -> Date = { Date() }) async throws -> URL {
        let card = try await account.perform({ client, token in try await client.person(personID, token: token) }, now: now())
        guard card.eligibility.permitsHandoff(at: now()), let phone = card.phone else { throw ClientError.invalidInput }
        let url = try telephoneURL(phone)
        guard let journal = account.journal, journal.snapshot.draft == nil, journal.snapshot.pending == nil else {
            throw ClientError.unfinishedOperation
        }
        // Durable BEFORE UIKit hands control to Phone. This is an unfinished
        // attempt, with no chosen outcome and no server submission.
        try journal.saveDraft(ConnectedDraft(personID: personID, now: now()))
        return url
    }
    static func telephoneURL(_ value: String) throws -> URL {
        let allowed = CharacterSet(charactersIn: "+0123456789 ()-.")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { throw ClientError.invalidInput }
        let number = value.filter { "+0123456789".contains($0) }
        let digits = number.hasPrefix("+") ? String(number.dropFirst()) : number
        guard (7...15).contains(digits.count), digits.allSatisfy({ "0123456789".contains($0) }),
              let url = URL(string: "tel:" + number) else { throw ClientError.invalidInput }
        return url
    }
}

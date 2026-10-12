import Foundation

/// Persisted with the input credential before the first request. Both clocks
/// must agree before replay; a changed clock or reboot requires human sign-in.
struct ExchangeRecovery: Codable, Sendable {
    let id: UUID
    let startedAt: Date
    let startedUptime: TimeInterval

    func timeout(now: Date, uptime: TimeInterval) throws -> TimeInterval {
        let wall = now.timeIntervalSince(startedAt)
        let monotonic = uptime - startedUptime
        guard wall >= 0, monotonic >= 0, abs(wall - monotonic) <= 2 else { throw ClientError.signInRequired }
        // Leave ten seconds for scheduling/transport uncertainty within the
        // server's fixed 120-second recovery window. Retrying never resets it.
        let remaining = 110 - max(wall, monotonic)
        guard remaining >= 1 else { throw ClientError.signInRequired }
        return min(30, remaining)
    }
}

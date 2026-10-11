import Foundation

/// Foreground idle locking on the monotonic system uptime, which ignores wall-clock changes.
/// Expiry is checked before an interaction is accepted.
struct IdleLock {
    static let minuteChoices = [1, 5, 15, 30, 60]
    static let defaultMinutes = 5

    private var lastActivity: TimeInterval?

    static func validatedMinutes(_ value: Int) -> Int {
        minuteChoices.contains(value) ? value : defaultMinutes
    }

    mutating func expired(now: TimeInterval, timeout: TimeInterval) -> Bool {
        guard let last = lastActivity else {
            lastActivity = now
            return false
        }
        return now < last || now - last >= timeout
    }

    /// Records activity; false (and nothing recorded) when the timeout already passed.
    mutating func activity(now: TimeInterval, timeout: TimeInterval) -> Bool {
        if expired(now: now, timeout: timeout) { return false }
        lastActivity = now
        return true
    }

    mutating func reset() {
        lastActivity = nil
    }
}

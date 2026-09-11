import Foundation

/// How long to wait before trying the Mac again, which is one rule in one place.
///
/// Doubling from a second and capped at thirty: a Mac that has gone to sleep is not coming back
/// inside a second, and a phone that keeps asking every second drains its battery for nothing.
/// The cap is what keeps the wait bounded when the Mac does come back — half a minute is the
/// longest anybody should hold an app that says it is trying.
///
/// The count is the caller's, because the caller is the one that knows a connection succeeded:
/// it resets to zero on a live session and on the app coming to the foreground.
public enum LinkBackoff {
    /// The first wait.
    public static let first: Duration = .seconds(1)
    /// The longest wait.
    public static let cap: Duration = .seconds(30)

    /// How long to wait after `attempt` failures, counting the first as one.
    public static func delay(after attempt: Int) -> Duration {
        guard attempt > 1 else { return first }
        let seconds = min(1 << min(attempt - 1, 16), 30)
        return .seconds(seconds)
    }
}

import Foundation

/// Runs a download again when it breaks, with a growing pause between tries.
///
/// A model is tens of gigabytes over a connection that will drop at least once, and the hub
/// client resumes a file from the bytes it already has. So a broken transfer is not a failure
/// yet: it is a reason to wait a moment and continue. Only a permanent answer — the repository
/// is not there, the token was refused — is worth stopping for, and the caller says which
/// errors those are, because the types differ by hub client.
///
/// Cancellation always passes straight through: a person who pressed Stop is not asking for
/// four more attempts. The pause is a `Task.sleep`, so Stop lands during a pause too.
public enum DownloadRetry {
    /// How many times a download is tried before it is given up on.
    public static let attempts = 5

    /// Whether an HTTP status is an answer rather than an accident: any client-side status
    /// except a timeout or a rate limit. Both hub clients apply the same rule, so it is here.
    public static func isPermanentStatus(_ code: Int) -> Bool {
        (400..<500).contains(code) && code != 408 && code != 429
    }

    /// What to tell someone once the tries are spent: the last reason, and that the next try
    /// resumes rather than starts over, which is the one thing worth knowing about a
    /// thirteen-gigabyte download that stopped at file three.
    public static func givingUpMessage(_ reason: String) -> String {
        let sentence = reason.hasSuffix(".") ? reason : reason + "."
        return "\(sentence) Try again to pick up where it left off."
    }

    /// The pause before try `attempt` (counting from 1, so the first pause is before the
    /// second try): 2, 4, 8, then 16 seconds, held there.
    public static func pause(before attempt: Int) -> Duration {
        .seconds(1 << min(max(attempt - 1, 1), 4))
    }

    /// Runs `body` until it returns, up to `attempts` times, pausing `pause(before:)` between
    /// tries. Rethrows the last error once the tries are spent, at once for an error
    /// `isPermanent` says is not worth retrying, and at once for a cancellation.
    ///
    /// `onRetry` is called with the attempt about to be made and the error that ended the last,
    /// for a log line; nothing else about the retry is visible from outside.
    public nonisolated(nonsending) static func run<Result>(
        attempts: Int = attempts,
        pause: (Int) -> Duration = pause(before:),
        isPermanent: (any Error) -> Bool,
        onRetry: (Int, any Error) -> Void = { _, _ in },
        _ body: () async throws -> Result
    ) async throws -> Result {
        precondition(attempts >= 1, "a download has to be tried at least once")
        var attempt = 1
        while true {
            do {
                return try await body()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A stopped transfer surfaces as a URL error the hub client wraps, not as
                // `CancellationError`, and a retry announced for a press of Stop is a lie.
                if Task.isCancelled { throw CancellationError() }
                guard attempt < attempts, !isPermanent(error) else { throw error }
                attempt += 1
                onRetry(attempt, error)
                try await Task.sleep(for: pause(attempt))
            }
        }
    }
}

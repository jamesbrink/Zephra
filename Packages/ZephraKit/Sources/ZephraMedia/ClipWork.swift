import Foundation

/// The blocking half of a clip's work, run on a queue of its own.
///
/// AVFoundation reads a frame with `copyNextSampleBuffer` and a track's sound with a reader
/// drained in a loop: both block the thread they are called on until the bytes have decoded,
/// and a clip a few seconds long is a second or two of that. On Swift's cooperative pool that
/// holds one of the handful of threads the whole app's concurrency shares. Every `ClipEditing`
/// call hands its blocking part to this queue instead, so no caller has to wrap one itself.
///
/// Concurrent rather than serial: two clips may be read at once — the app reads a tail while
/// a chain joins its passes — and one waiting on the other would be a stall of its own.
enum ClipWork {
    private static let queue = DispatchQueue(
        label: "io.zephra.clip-editing", qos: .userInitiated, attributes: .concurrent)

    /// Runs `work` on the clip queue and answers what it returned.
    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: work)) }
        }
    }
}

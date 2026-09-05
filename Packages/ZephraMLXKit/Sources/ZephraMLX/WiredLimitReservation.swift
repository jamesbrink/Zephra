import MLX

/// The one long-lived wired-memory reservation, replaced in the order it was asked for.
///
/// mlx-swift hands the wired limit out as tickets on an actor, and a ticket is started and
/// ended on the actor's own time. Replacing one with a task per request left the order to the
/// scheduler: the second task could end a ticket the first had not started yet, and the first
/// would then start its own beside the second's — two active tickets under `WiredSumPolicy`,
/// double the limit, and in Debug the assertion mlx-swift raises when a ticket is started
/// twice. Here every request is a value on one stream and one consumer does both halves, so
/// the tickets follow the requests, and at no moment are two of them active.
///
/// No lock and no `nonisolated(unsafe)`: the consumer's ticket is a local of its own task.
final class WiredLimitReservation: Sendable {
    static let shared = WiredLimitReservation()

    private let requests: AsyncStream<Int>.Continuation

    private init() {
        let (stream, continuation) = AsyncStream<Int>.makeStream(bufferingPolicy: .unbounded)
        requests = continuation
        let policy = WiredSumPolicy()
        Task.detached {
            var current: WiredMemoryTicket?
            for await bytes in stream {
                if let current { _ = await current.end() }
                let next = policy.ticket(size: bytes, kind: .active)
                _ = await next.start()
                current = next
            }
        }
    }

    /// Ends the reservation in force and starts one of `bytes`, after every request before it.
    func replace(bytes: Int) {
        requests.yield(bytes)
    }
}

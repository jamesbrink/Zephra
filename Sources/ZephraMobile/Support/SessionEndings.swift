import Foundation

/// One iterator over a client's endings, off the main actor, so waiting on it is not a mutation
/// of actor-isolated state — and kept, since an `AsyncStream` iterator that is dropped ends the
/// stream behind it. Single consumer by construction: `LinkReconnect` is the only thing that
/// waits on one.
nonisolated final class SessionEndings: @unchecked Sendable {
    private var iterator: AsyncStream<Void>.AsyncIterator

    init(_ stream: AsyncStream<Void>) { iterator = stream.makeAsyncIterator() }

    /// The next ending, or nil once there will be no more.
    func next() async -> Void? { await iterator.next() }
}

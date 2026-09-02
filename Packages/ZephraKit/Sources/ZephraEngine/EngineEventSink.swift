/// The write end of an engine's event stream, small and Sendable so it can be handed to the
/// inference actor and called from the backend's own queue without any further ceremony.
public struct EngineEventSink: Sendable {
    private let continuation: AsyncStream<EngineEvent>.Continuation

    /// Wraps the continuation of a stream the caller is already consuming.
    public init(_ continuation: AsyncStream<EngineEvent>.Continuation) {
        self.continuation = continuation
    }

    /// Offers one event to the stream. Never blocks, and drops the oldest event when the
    /// consumer has fallen behind, because only the newest progress matters.
    public func send(_ event: EngineEvent) {
        continuation.yield(event)
    }
}

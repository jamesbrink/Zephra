/// Carries one operation's progress events from the inference queue to the main actor.
///
/// The stream buffers only the newest few events: progress is a snapshot, not a log, so a
/// backlog is worth dropping rather than replaying. The pump owns the draining task and does
/// not return until every event has been applied, which keeps the state the caller sets after
/// an operation from being overwritten by an event that was still in flight.
@MainActor
struct EngineEventPump {
    /// How many events may wait for the main actor before the oldest is discarded.
    private static let bufferSize = 4

    private let apply: @MainActor @Sendable (EngineEvent) -> Void

    /// Creates a pump that hands every event to `apply` on the main actor.
    init(_ apply: @escaping @MainActor @Sendable (EngineEvent) -> Void) {
        self.apply = apply
    }

    /// Runs `body` with a sink wired to this pump, draining the stream before returning or
    /// rethrowing, so the caller can set a final state without racing a late event.
    func run<Value>(_ body: (EngineEventSink) async throws -> Value) async throws -> Value {
        let (stream, continuation) = AsyncStream.makeStream(
            of: EngineEvent.self,
            bufferingPolicy: .bufferingNewest(Self.bufferSize)
        )
        let apply = self.apply
        let drain = Task {
            for await event in stream { apply(event) }
        }
        do {
            let value = try await body(EngineEventSink(continuation))
            continuation.finish()
            await drain.value
            return value
        } catch {
            continuation.finish()
            await drain.value
            throw error
        }
    }
}

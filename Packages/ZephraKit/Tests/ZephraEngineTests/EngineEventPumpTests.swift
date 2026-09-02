import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("EngineEventPump")
struct EngineEventPumpTests {
    @Test("every event is applied, in order, before run returns")
    func drainsBeforeReturning() async throws {
        let seen = EventLog()
        let pump = EngineEventPump { seen.record($0) }

        let value = try await pump.run { sink in
            for step in 1...3 { sink.send(Self.event(step: step)) }
            return "finished"
        }

        #expect(value == "finished")
        #expect(seen.steps == [1, 2, 3])
    }

    @Test("a backlog is dropped rather than replayed, and the newest event still lands")
    func backlogIsDropped() async throws {
        let seen = EventLog()
        let pump = EngineEventPump { seen.record($0) }

        // Nothing awaits inside the body, so the main actor cannot drain until it ends: this
        // is the backlog the buffering policy exists for.
        try await pump.run { sink in
            for step in 1...40 { sink.send(Self.event(step: step)) }
        }

        #expect(seen.steps.count < 40, "a backlog should be dropped, not replayed")
        #expect(seen.steps.last == 40, "the newest progress must always arrive")
        #expect(seen.steps == seen.steps.sorted(), "what does arrive must stay in order")
    }

    @Test("a body that throws still drains what it already sent")
    func drainsOnThrow() async throws {
        let seen = EventLog()
        let pump = EngineEventPump { seen.record($0) }

        await #expect(throws: BackendError.generationFailed("kernel panic")) {
            try await pump.run { sink in
                sink.send(Self.event(step: 1))
                throw BackendError.generationFailed("kernel panic")
            }
        }
        #expect(seen.steps == [1])
    }

    private static func event(step: Int) -> EngineEvent {
        .progress(GenerationProgressEvent(phase: .denoising(step: step, of: 40), fraction: 0))
    }
}

/// The events the pump applied, in the order it applied them.
@MainActor
private final class EventLog {
    private(set) var steps: [Int] = []

    func record(_ event: EngineEvent) {
        guard case .progress(let progress) = event,
              case .denoising(let step, _) = progress.phase
        else { return }
        steps.append(step)
    }
}

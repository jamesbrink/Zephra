import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("InferenceActor")
struct InferenceActorTests {
    @Test("generating before anything is loaded fails as a load failure")
    func generateBeforeLoad() async throws {
        let control = MockBackendControl()
        let registry = BackendRegistry().registering(.zImage) { _ in MockBackend(control: control) }
        let inference = InferenceActor(registry: registry)
        let (_, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        defer { continuation.finish() }

        await #expect(throws: BackendError.loadFailed("The model has not been loaded yet.")) {
            _ = try await inference.generate(
                GenerationSettings.defaults(for: ModelCatalog.default),
                events: EngineEventSink(continuation)
            )
        }
        #expect(control.settings.generations == 0, "the backend must not even be built")
    }

    @Test("preparing twice loads once, because the weights are already in memory")
    func prepareIsIdempotent() async throws {
        let control = MockBackendControl()
        let registry = BackendRegistry().registering(.zImage) { _ in MockBackend(control: control) }
        let inference = InferenceActor(registry: registry)
        let (stream, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        let sink = EngineEventSink(continuation)

        try await inference.prepare(ModelCatalog.default, events: sink)
        try await inference.prepare(ModelCatalog.default, events: sink)
        continuation.finish()
        for await _ in stream {}

        #expect(control.settings.loads == 1)
    }
}

import Foundation
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

    @Test("with no upscaler in the build, asking for one fails as weights missing")
    func upscaleWithoutAFactory() async throws {
        let inference = InferenceActor(registry: BackendRegistry())
        let (_, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        defer { continuation.finish() }

        await #expect(throws: UpscaleError.self) {
            _ = try await inference.upscale(
                MockBackend.pngData, UpscaleRequest(factor: 2),
                events: EngineEventSink(continuation))
        }
    }

    @Test("the upscaler is built once and reports a tile at a time")
    func upscaleReportsTiles() async throws {
        let dial = MockUpscalerControl()
        dial.update { $0.tiles = 4 }
        let inference = InferenceActor(
            registry: BackendRegistry(), upscaler: { MockUpscaler(control: dial) })
        let (stream, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        let sink = EngineEventSink(continuation)

        let first = try await inference.upscale(
            MockBackend.pngData, UpscaleRequest(factor: 4), events: sink)
        _ = try await inference.upscale(MockBackend.pngData, UpscaleRequest(factor: 2), events: sink)
        continuation.finish()
        for await _ in stream {}

        #expect(first == MockUpscaler.pngData)
        #expect(dial.settings.upscales == 2)
        #expect(dial.settings.lastFactor == 2)
        #expect(dial.settings.tilesEmitted == 8, "four tiles each time")
    }

    @Test("unloading the model leaves the upscaler where it is")
    func unloadDoesNotDropTheUpscaler() async throws {
        let dial = MockUpscalerControl()
        let control = MockBackendControl()
        let registry = BackendRegistry().registering(.zImage) { _ in MockBackend(control: control) }
        let inference = InferenceActor(registry: registry, upscaler: { MockUpscaler(control: dial) })
        let (_, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        defer { continuation.finish() }
        let sink = EngineEventSink(continuation)

        _ = try await inference.upscale(MockBackend.pngData, UpscaleRequest(factor: 2), events: sink)
        await inference.unload()
        _ = try await inference.upscale(MockBackend.pngData, UpscaleRequest(factor: 2), events: sink)

        #expect(dial.settings.unloads == 0, "the upscaler is not the model")
        #expect(dial.settings.upscales == 2)
    }
}

@Suite("InferenceActor residency")
struct InferenceActorResidencyTests {
    @Test("the residency reaches the backend, and asking for the other one is a reload")
    func residencyIsPinnedBesideThePath() async throws {
        let control = MockBackendControl()
        let registry = BackendRegistry().registering(.zImage) { _ in MockBackend(control: control) }
        let inference = InferenceActor(registry: registry)
        let (stream, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        let sink = EngineEventSink(continuation)

        try await inference.prepare(ModelCatalog.default, residency: .streamed, events: sink)
        #expect(control.settings.lastResidency == .streamed)
        try await inference.prepare(ModelCatalog.default, residency: .streamed, events: sink)
        #expect(control.settings.loads == 1, "the same residency is already up")
        try await inference.prepare(ModelCatalog.default, residency: .resident, events: sink)
        #expect(control.settings.loads == 2, "the other residency is a reload")
        #expect(control.settings.lastResidency == .resident)
        continuation.finish()
        for await _ in stream {}
    }
}

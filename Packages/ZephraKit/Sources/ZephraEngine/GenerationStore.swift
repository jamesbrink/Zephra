import Foundation
import Observation
import ZephraCore

/// The single object the UI observes. Owns the engine's state and the images it produced.
///
/// STUB: public surface is frozen; bodies are filled in by the engine work package.
@MainActor
@Observable
public final class GenerationStore {
    /// What the engine is doing right now.
    public private(set) var state: EngineState = .idle
    /// The image shown on the canvas.
    public private(set) var current: GeneratedImage?
    /// This session's images, newest first, capped at 24.
    public private(set) var history: [GeneratedImage] = []
    /// What the next generation will use. Edited directly by the UI.
    public var settings: GenerationSettings
    /// The model this store drives.
    public private(set) var descriptor: ModelDescriptor
    /// Wall-clock time of the last completed generation.
    public private(set) var lastDuration: Duration?

    private let backendFactory: BackendFactory
    private let outputDirectory: URL?

    /// Creates a store for one model. `outputDirectory` nil means ~/Pictures/Zephra.
    public init(
        descriptor: ModelDescriptor = ModelCatalog.default,
        backendFactory: @escaping BackendFactory,
        outputDirectory: URL? = nil
    ) {
        self.descriptor = descriptor
        self.settings = GenerationSettings.defaults(for: descriptor)
        self.backendFactory = backendFactory
        self.outputDirectory = outputDirectory
    }

    /// True when a generation can start: the engine is ready and there is a prompt.
    public var canGenerate: Bool { state.acceptsGeneration && settings.isReadyToGenerate }

    /// Finds or downloads the model, loads it, and warms up. Call once from the root view.
    public func bootstrap() async {}

    /// Starts a generation with the current settings. Safe to call only when `canGenerate`.
    public func generate() {}

    /// Stops the in-flight generation after its current step.
    public func cancel() {}

    /// Leaves `.failed` and runs `bootstrap` again.
    public func retry() {}

    /// Shows an earlier image on the canvas and adopts its settings.
    public func select(_ image: GeneratedImage) {}

    /// Picks a fresh seed for the next generation.
    public func randomizeSeed() { settings = settings.withRandomSeed() }

    /// A store frozen in one state, for SwiftUI previews. Never touches a backend.
    public static func preview(state: EngineState, image: GeneratedImage? = nil) -> GenerationStore {
        let store = GenerationStore(backendFactory: { _ in fatalError("preview store has no backend") })
        store.state = state
        store.current = image
        store.history = image.map { [$0] } ?? []
        store.settings.prompt = "A lighthouse at dusk, fog rolling in over black rocks"
        return store
    }
}

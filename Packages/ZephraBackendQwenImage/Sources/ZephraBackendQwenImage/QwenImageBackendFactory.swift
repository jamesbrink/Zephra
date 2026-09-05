import ZephraCore
import ZephraMLX

/// The one symbol a composition root needs in order to wire Qwen-Image into the engine.
public nonisolated enum QwenImageBackendFactory {
    /// The VAE tile the engine chose for the run about to start: written through `runtime`,
    /// read by every backend this factory makes as it builds a request. One slot per family,
    /// under a lock, where a `nonisolated(unsafe)` static in the kit used to be.
    private static let tile = VAETileSetting()

    /// A factory for fresh, idle `QwenImageBackend`s running under `environment`, the switches
    /// the composition root read once.
    public static func make(_ environment: InferenceEnvironment) -> BackendFactory {
        { _ in QwenImageBackend(environment: environment, tile: tile) }
    }

    /// The shared MLX runtime with this family's autoencoder tile behind it. The allocator's
    /// limits and readings are process-wide; only the tile is Qwen-Image's own.
    public static var runtime: any InferenceRuntime { MLXInferenceRuntime(tile: tile) }
}

import ZephraCore
import ZephraMLX

/// The one symbol a composition root needs in order to wire Z-Image into the engine.
///
/// The engine takes a factory rather than a backend because backends are not Sendable, so the
/// engine has to build one inside its own isolation. The descriptor is ignored: every model
/// this backend serves runs through the same pipeline, and the descriptor arrives again at
/// `ensureAvailable`.
public nonisolated enum ZImageBackendFactory {
    /// The VAE tile the engine chose for the run about to start: written through `runtime`,
    /// read by every backend this factory makes as it builds a request, and handed to the
    /// vendored kit's own knob for that run. One slot per family, under a lock.
    private static let tile = VAETileSetting()

    /// A factory for fresh, idle `ZImageBackend`s running under `environment`, the switches
    /// the composition root read once.
    public static func make(_ environment: InferenceEnvironment) -> BackendFactory {
        { _ in ZImageBackend(environment: environment, tile: tile) }
    }

    /// The shared MLX runtime with this family's autoencoder tile behind it. The allocator's
    /// limits and readings are process-wide; only the tile is Z-Image's own.
    public static var runtime: any InferenceRuntime { MLXInferenceRuntime(tile: tile) }
}

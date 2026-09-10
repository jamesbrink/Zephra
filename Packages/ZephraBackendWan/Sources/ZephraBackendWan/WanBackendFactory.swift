import ZephraCore
import ZephraMLX

/// The one public entry point: how the app registers this family without naming its types.
public nonisolated enum WanBackendFactory {
    /// The VAE tile the engine chose for the run about to start: written through `runtime`,
    /// read by every backend this factory makes. One slot per family, under a lock, as every
    /// family has; the decoder tiles spatially at it, scaled to its own cell.
    private static let tile = VAETileSetting()

    /// A factory for fresh, idle backends running under `environment`, the switches the
    /// composition root read once. The descriptor is ignored because one backend serves every
    /// variant of the family; it arrives again at `ensureAvailable`.
    public static func make(_ environment: InferenceEnvironment) -> BackendFactory {
        { _ in WanBackend(environment: environment, tile: tile) }
    }

    /// The shared MLX runtime with this family's tile slot behind it. The allocator's limits
    /// and readings are process-wide; only the tile is this family's own.
    public static var runtime: any InferenceRuntime { MLXInferenceRuntime(tile: tile) }
}

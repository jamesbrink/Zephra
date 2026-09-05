import ZephraCore
import ZephraMLX

/// The one symbol a composition root needs in order to wire Z-Image into the engine.
///
/// The engine takes a factory rather than a backend because backends are not Sendable, so the
/// engine has to build one inside its own isolation. The descriptor is ignored: every model
/// this backend serves runs through the same pipeline, and the descriptor arrives again at
/// `ensureAvailable`.
public nonisolated enum ZImageBackendFactory {
    /// Makes a fresh, idle `ZImageBackend`.
    public static let make: BackendFactory = { _ in ZImageBackend() }

    /// The shared MLX runtime with this family's autoencoder tile behind it. The allocator's
    /// limits and readings are process-wide; only the tile is Z-Image's own.
    public static var runtime: any InferenceRuntime {
        MLXInferenceRuntime(
            tile: .init(
                read: { ZImageRuntime.vaeTileSize },
                write: { ZImageRuntime.vaeTileSize = $0 }))
    }
}

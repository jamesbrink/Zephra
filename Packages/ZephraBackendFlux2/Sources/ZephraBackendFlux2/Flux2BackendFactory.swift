import ZephraCore
import ZephraMLX

/// The one public entry point: how the app registers this family without naming its types.
public nonisolated enum Flux2BackendFactory {
    /// Builds a fresh, idle backend. The descriptor is ignored because one backend serves every
    /// variant of the family; it arrives again at `ensureAvailable`.
    public static let make: BackendFactory = { _ in Flux2Backend() }

    /// The shared MLX runtime with this family's autoencoder tile behind it. The allocator's
    /// limits and readings are process-wide; only the tile is klein's own.
    public static var runtime: any InferenceRuntime {
        MLXInferenceRuntime(
            tile: .init(
                read: { Flux2Runtime.vaeTileSize },
                write: { Flux2Runtime.vaeTileSize = $0 }))
    }
}

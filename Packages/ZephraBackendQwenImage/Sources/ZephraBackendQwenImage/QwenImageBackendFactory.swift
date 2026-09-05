import ZephraCore
import ZephraMLX

/// The one symbol a composition root needs in order to wire Qwen-Image into the engine.
public nonisolated enum QwenImageBackendFactory {
    /// Makes a fresh, idle `QwenImageBackend`.
    public static let make: BackendFactory = { _ in QwenImageBackend() }

    /// The shared MLX runtime with this family's autoencoder tile behind it. The allocator's
    /// limits and readings are process-wide; only the tile is Qwen-Image's own.
    public static var runtime: any InferenceRuntime {
        MLXInferenceRuntime(
            tile: .init(
                read: { QwenImageRuntime.vaeTileSize },
                write: { QwenImageRuntime.vaeTileSize = $0 }))
    }
}

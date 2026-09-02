import Foundation
import MLX
import QwenImage

/// Tuning knobs for the MLX runtime that backs Qwen-Image, kept here so nothing above this layer
/// has to import MLX to set them.
///
/// The allocator itself is process-wide — one copy of MLX serves every family — so the limits
/// below are the same knobs Z-Image's runtime turns. The tile size is not: it belongs to this
/// pipeline's autoencoder, and a host sets it for the model that is about to run.
public nonisolated enum QwenImageRuntime {
    /// Sets the GPU allocator's limits. `nil` leaves a limit at whatever MLX chose.
    public static func configure(cacheLimitBytes: Int?, memoryLimitBytes: Int?) {
        if let cacheLimitBytes {
            Memory.cacheLimit = cacheLimitBytes
        }
        if let memoryLimitBytes {
            Memory.memoryLimit = memoryLimitBytes
        }
    }

    /// The latent-space tile edge the VAE decode runs at, or nil for the exact untiled decode.
    ///
    /// Starts at whatever `ZEPHRA_VAE_TILE` said at launch, which is how the benchmark sets it.
    /// Assigning takes effect on the next decode; nothing reloads.
    public static var vaeTileSize: Int? {
        get { QwenImageAutoencoder.latentTile }
        set { QwenImageAutoencoder.latentTile = newValue }
    }

    /// Current GPU memory use in bytes: what is live, what is cached for reuse, and the high
    /// water mark since the process started.
    public static func memorySnapshot() -> (active: Int, cache: Int, peak: Int) {
        let snapshot = Memory.snapshot()
        return (snapshot.activeMemory, snapshot.cacheMemory, snapshot.peakMemory)
    }
}

import Foundation
import MLX
import ZImage

/// Tuning knobs for the MLX runtime that backs Z-Image, kept here so nothing above this layer
/// has to import MLX to set them.
public nonisolated enum ZImageRuntime {
    /// Sets the GPU allocator's limits.
    ///
    /// The cache limit caps the memory MLX holds on to between allocations. Left uncapped it
    /// will happily keep every scratch buffer a 1024-pixel run touched, which on a 16 GB Mac
    /// pushes the machine into swap. `nil` leaves a limit at whatever MLX chose.
    ///
    /// - Parameters:
    ///   - cacheLimitBytes: Ceiling on retained scratch memory, or nil to leave it alone.
    ///   - memoryLimitBytes: Ceiling on total allocation, or nil to leave it alone.
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
    /// Starts at whatever `ZEPHRA_VAE_TILE` said at launch, which is how the benchmark still
    /// sets it. Assigning takes effect on the next decode; nothing reloads.
    public static var vaeTileSize: Int? {
        get { VAETiledDecode.latentTile }
        set { VAETiledDecode.latentTile = newValue }
    }

    /// One line naming the Metal device and the memory it will work within, for logs and for
    /// the benchmark header.
    public static func deviceSummary() -> String {
        let info = GPU.deviceInfo()
        let working = Double(info.maxRecommendedWorkingSetSize) / 1_000_000_000
        let system = Double(info.memorySize) / 1_000_000_000
        return String(
            format: "%@, %.1f GB working set, %.1f GB system memory",
            info.architecture,
            working,
            system
        )
    }

    /// Current GPU memory use in bytes: what is live, what is cached for reuse, and the high
    /// water mark since the process started.
    public static func memorySnapshot() -> (active: Int, cache: Int, peak: Int) {
        let snapshot = Memory.snapshot()
        return (snapshot.activeMemory, snapshot.cacheMemory, snapshot.peakMemory)
    }
}

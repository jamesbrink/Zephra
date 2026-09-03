import Foundation
import MLX
import ZephraCore

/// The process-wide MLX allocator's knobs and readouts.
///
/// One copy of MLX serves every family, so a limit set here or a reading taken here is the same
/// answer whichever backend is asked. Each family's own runtime type adds the one thing that
/// really is its own — the tile its autoencoder decodes in — and leaves the allocator to this.
public nonisolated enum MLXRuntime {
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

    /// Current GPU memory use: what is live, what is cached for reuse, and the high-water mark
    /// since the process started.
    public static func memorySnapshot() -> MemorySnapshot {
        let snapshot = Memory.snapshot()
        return MemorySnapshot(
            activeBytes: snapshot.activeMemory,
            cacheBytes: snapshot.cacheMemory,
            peakBytes: snapshot.peakMemory
        )
    }

    /// One line naming the Metal device and the memory it will work within, for logs and for
    /// the benchmark header.
    public static func deviceSummary() -> String {
        let info = GPU.deviceInfo()
        let working = Double(info.maxRecommendedWorkingSetSize) / 1_000_000_000
        let system = Double(info.memorySize) / 1_000_000_000
        return String(
            format: "%@, %.1f GB working set, %.1f GB system memory",
            info.architecture, working, system)
    }
}

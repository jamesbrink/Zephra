import Foundation
import MLX
import ZephraCore

/// The process-wide MLX allocator's knobs and readouts.
///
/// One copy of MLX serves every family, so a limit set here or a reading taken here is the same
/// answer whichever backend is asked. `MLXInferenceRuntime` is this behind the `InferenceRuntime`
/// protocol, with the one thing that really is a family's own — the tile its autoencoder
/// decodes in — handed in by the family.
public nonisolated enum MLXRuntime {
    public static func synchronize() {
        Stream.gpu.synchronize()
        Stream.cpu.synchronize()
    }

    /// Sets the GPU allocator's limits.
    ///
    /// The cache limit caps the memory MLX holds on to between allocations. Left uncapped it
    /// will happily keep every scratch buffer a 1024-pixel run touched, which on a 16 GB Mac
    /// pushes the machine into swap. `nil` leaves a limit at whatever MLX chose.
    ///
    /// - Parameters:
    ///   - cacheLimitBytes: Ceiling on retained scratch memory, or nil to leave it alone.
    ///   - memoryLimitBytes: Ceiling on total allocation, or nil to leave it alone.
    ///   - wiredLimitBytes: Ceiling on what MLX keeps wired in the GPU's residency set, or nil
    ///     to leave it alone. Clamped to the working set: MLX warns above it, and a model wired
    ///     past what the GPU may keep is exactly the paging the limit exists to prevent.
    public static func configure(
        cacheLimitBytes: Int?, memoryLimitBytes: Int?, wiredLimitBytes: Int? = nil
    ) {
        if let cacheLimitBytes {
            Memory.cacheLimit = cacheLimitBytes
        }
        if let memoryLimitBytes {
            Memory.memoryLimit = memoryLimitBytes
        }
        if let wiredLimitBytes {
            let ceiling = GPU.maxRecommendedWorkingSetBytes() ?? wiredLimitBytes
            setWiredLimit(min(wiredLimitBytes, ceiling))
        }
    }

    /// Replaces the one long-lived reservation that keeps MLX's residency set at the wired limit.
    ///
    /// MLX starts with a wired limit of zero: nothing but its heap is kept resident, and the
    /// OS may page a buffer it has not touched for a while. The reservation is replaced on the
    /// ticket actor's own time, in the order asked; see `WiredLimitReservation`.
    private static func setWiredLimit(_ bytes: Int) {
        WiredLimitReservation.shared.replace(bytes: bytes)
    }

    /// Bytes the GPU may keep resident: Metal's recommended working set, which macOS sets at
    /// roughly three quarters of RAM and `iogpu.wired_limit_mb` raises. Read once per launch;
    /// a change to the sysctl is seen at the next one.
    public static func gpuWorkingSetBytes() -> UInt64 {
        GPU.deviceInfo().maxRecommendedWorkingSetSize
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

    /// What the last streamed pass read and how fast, or nil while nothing has streamed.
    public static func weightStreamReading() -> WeightStreamReading? {
        WeightStreamMeter.lastPass
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

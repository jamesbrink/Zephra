import ZephraCore
import ZephraMLX

/// This family's view of the shared MLX runtime: the process-wide allocator's limits and
/// readings, plus its own autoencoder tile.
public struct Flux2InferenceRuntime: InferenceRuntime {
    /// Creates the runtime handle. Nothing is touched until a method is called.
    public init() {}

    public func synchronize() { MLXRuntime.synchronize() }

    public func setCacheLimit(bytes: Int) {
        MLXRuntime.configure(cacheLimitBytes: bytes, memoryLimitBytes: nil)
    }

    public func setMemoryLimit(bytes: Int) {
        MLXRuntime.configure(cacheLimitBytes: nil, memoryLimitBytes: bytes)
    }

    public func setWiredLimit(bytes: Int) {
        MLXRuntime.configure(cacheLimitBytes: nil, memoryLimitBytes: nil, wiredLimitBytes: bytes)
    }

    public func gpuWorkingSetBytes() -> UInt64? {
        MLXRuntime.gpuWorkingSetBytes()
    }

    public func setVAETileSize(_ tile: Int?) {
        Flux2Runtime.vaeTileSize = tile
    }

    public func vaeTileSize() -> Int? {
        Flux2Runtime.vaeTileSize
    }

    public func memorySnapshot() -> MemorySnapshot {
        MLXRuntime.memorySnapshot()
    }

    public func deviceSummary() -> String {
        MLXRuntime.deviceSummary()
    }
}

import ZephraCore
import ZephraMLX

/// The MLX runtime as something the app can hold and hand to a view, so the settings window can
/// read and change the allocator without importing MLX. The allocator answers come from
/// `MLXRuntime`, which every family shares; the tile is `ZImageRuntime`'s.
public struct ZImageInferenceRuntime: InferenceRuntime {
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

    public func weightStreamReading() -> WeightStreamReading? {
        MLXRuntime.weightStreamReading()
    }

    public func setVAETileSize(_ tile: Int?) {
        ZImageRuntime.vaeTileSize = tile
    }

    public func vaeTileSize() -> Int? {
        ZImageRuntime.vaeTileSize
    }

    public func memorySnapshot() -> MemorySnapshot {
        MLXRuntime.memorySnapshot()
    }

    public func deviceSummary() -> String {
        MLXRuntime.deviceSummary()
    }
}

import ZephraCore

/// `ZImageRuntime` as something the app can hold and hand to a view, so the settings window can
/// read and change MLX's allocator without importing MLX.
public struct ZImageInferenceRuntime: InferenceRuntime {
    public init() {}

    public func setCacheLimit(bytes: Int) {
        ZImageRuntime.configure(cacheLimitBytes: bytes, memoryLimitBytes: nil)
    }

    public func memorySnapshot() -> MemorySnapshot {
        let snapshot = ZImageRuntime.memorySnapshot()
        return MemorySnapshot(
            activeBytes: snapshot.active,
            cacheBytes: snapshot.cache,
            peakBytes: snapshot.peak
        )
    }
}

import ZephraCore

/// `QwenImageRuntime` as something the app can hold and hand to a view, so the settings window
/// can read and change MLX's allocator without importing MLX.
public struct QwenImageInferenceRuntime: InferenceRuntime {
    public init() {}

    public func setCacheLimit(bytes: Int) {
        QwenImageRuntime.configure(cacheLimitBytes: bytes, memoryLimitBytes: nil)
    }

    public func setVAETileSize(_ tile: Int?) {
        QwenImageRuntime.vaeTileSize = tile
    }

    public func vaeTileSize() -> Int? {
        QwenImageRuntime.vaeTileSize
    }

    public func memorySnapshot() -> MemorySnapshot {
        let snapshot = QwenImageRuntime.memorySnapshot()
        return MemorySnapshot(
            activeBytes: snapshot.active,
            cacheBytes: snapshot.cache,
            peakBytes: snapshot.peak
        )
    }
}

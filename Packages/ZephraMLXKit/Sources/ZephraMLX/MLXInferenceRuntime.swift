import ZephraCore

/// The MLX runtime as something a host can hold and hand to a view, so the settings window can
/// read and tune the allocator without importing MLX.
///
/// One copy of MLX serves every family, so the allocator's limits and readings are the same
/// answer whichever backend is asked, and every one of them is `MLXRuntime`'s. The one thing
/// that really is a family's own — the tile its autoencoder decodes in — is a `VAETileSetting`
/// the family's factory shares between this handle and the backends it makes, which is how
/// three families share one runtime type without this package naming any of them.
public struct MLXInferenceRuntime: InferenceRuntime {
    private let tile: VAETileSetting

    /// Creates the runtime handle over `tile`. Nothing is touched until a method is called.
    public init(tile: VAETileSetting) {
        self.tile = tile
    }

    public func synchronize() { MLXRuntime.synchronize() }

    /// Whether the driver has stopped running this process's command buffers — an ignored
    /// submission, which nothing but a relaunch clears. Sticky for the rest of the launch, so
    /// the engine can close admission and stop handing Metal work to a device that refuses it.
    public var isDeviceLost: Bool { DeviceFaultSink.faults.isLost }

    public func isM5ClassGPU() -> Bool { GPUGeneration.isM5Class }

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
        self.tile.value = tile
    }

    public func vaeTileSize() -> Int? {
        tile.value
    }

    public func releaseCache() {
        MLXRuntime.releaseCache()
    }

    public func memorySnapshot() -> MemorySnapshot {
        MLXRuntime.memorySnapshot()
    }

    public func deviceSummary() -> String {
        MLXRuntime.deviceSummary()
    }
}

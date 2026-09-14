import ZephraCore

/// Every registered backend's runtime, turned as one knob.
///
/// The allocator is process-wide, so a cache limit, a memory limit or a memory reading is the
/// same allocator whichever backend is asked: the limits are written to the first runtime and
/// the readings taken from it, and writing a limit to all of them would set the one allocator
/// three times — for the wired limit, three reservations replacing each other for no reason.
/// The tile size is not process-wide: it is a variable of one pipeline's autoencoder, and only
/// the loaded family's copy is ever read. Writing it to all of them means the app can apply the
/// policy for the model about to run without asking which family that is, and a family that is
/// not loaded is left holding a number nothing looks at.
///
/// This names no backend. `ZephraApp` builds it from the concrete runtimes, which is the one
/// place allowed to know what they are.
struct CombinedInferenceRuntime: InferenceRuntime {
    private let runtimes: [any InferenceRuntime]

    /// Creates a runtime that sets the allocator's limits through the first of `runtimes` and
    /// reads from it, and writes the tile to every one of them.
    init(_ runtimes: [any InferenceRuntime]) {
        self.runtimes = runtimes
    }

    func synchronize() { runtimes.first?.synchronize() }

    func setCacheLimit(bytes: Int) {
        runtimes.first?.setCacheLimit(bytes: bytes)
    }

    func setMemoryLimit(bytes: Int) {
        runtimes.first?.setMemoryLimit(bytes: bytes)
    }

    func setWiredLimit(bytes: Int) {
        runtimes.first?.setWiredLimit(bytes: bytes)
    }

    func gpuWorkingSetBytes() -> UInt64? {
        runtimes.first?.gpuWorkingSetBytes()
    }

    func weightStreamReading() -> WeightStreamReading? {
        runtimes.first?.weightStreamReading()
    }

    func deviceSummary() -> String {
        runtimes.first?.deviceSummary() ?? ""
    }

    func setVAETileSize(_ tile: Int?) {
        for runtime in runtimes { runtime.setVAETileSize(tile) }
    }

    func vaeTileSize() -> Int? {
        runtimes.first?.vaeTileSize()
    }

    func isM5ClassGPU() -> Bool {
        runtimes.first?.isM5ClassGPU() ?? false
    }

    func releaseCache() {
        runtimes.first?.releaseCache()
    }

    /// MLX's handler stack is process-wide, so a boundary opened on any one of these is the
    /// boundary every family's work runs inside. The first is enough, exactly as it is for the
    /// allocator's limits; opening one per runtime would nest the same handler five deep.
    nonisolated(nonsending) func catchingDeviceErrors<R>(_ body: () async throws -> R)
        async throws -> R
    {
        guard let first = runtimes.first else { return try await body() }
        return try await first.catchingDeviceErrors(body)
    }

    /// One global handler, installed through the first, for the same reason.
    func installDeviceErrorLogging() {
        runtimes.first?.installDeviceErrorLogging()
    }

    func memorySnapshot() -> MemorySnapshot {
        runtimes.first?.memorySnapshot() ?? MemorySnapshot(
            activeBytes: 0, cacheBytes: 0, peakBytes: 0)
    }
}

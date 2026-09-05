import ZephraCore

/// Every registered backend's runtime, turned as one knob.
///
/// The allocator is process-wide, so a cache limit or a memory reading is the same answer
/// whichever backend gives it. The tile size is not: it is a variable of one pipeline's
/// autoencoder, and only the loaded family's copy is ever read. Writing it to all of them means
/// the app can apply the policy for the model about to run without asking which family that is,
/// and a family that is not loaded is left holding a number nothing looks at.
///
/// This names no backend. `ZephraApp` builds it from the concrete runtimes, which is the one
/// place allowed to know what they are.
struct CombinedInferenceRuntime: InferenceRuntime {
    private let runtimes: [any InferenceRuntime]

    /// Creates a runtime that writes to every one of `runtimes` and reads from the first,
    /// which is right only because every reading is process-wide or was written to all of them.
    init(_ runtimes: [any InferenceRuntime]) {
        self.runtimes = runtimes
    }

    func synchronize() { runtimes.first?.synchronize() }

    func setCacheLimit(bytes: Int) {
        for runtime in runtimes { runtime.setCacheLimit(bytes: bytes) }
    }

    func setMemoryLimit(bytes: Int) {
        for runtime in runtimes { runtime.setMemoryLimit(bytes: bytes) }
    }

    func setWiredLimit(bytes: Int) {
        for runtime in runtimes { runtime.setWiredLimit(bytes: bytes) }
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

    func memorySnapshot() -> MemorySnapshot {
        runtimes.first?.memorySnapshot() ?? MemorySnapshot(
            activeBytes: 0, cacheBytes: 0, peakBytes: 0)
    }
}

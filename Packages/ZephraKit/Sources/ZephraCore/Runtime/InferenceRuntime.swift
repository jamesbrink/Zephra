/// The knobs and readouts of whatever GPU runtime a backend is built on.
///
/// Kept apart from `ImageGenerationBackend` on purpose: this is the process-wide allocator, not
/// one model, and the settings window needs it while no model is loaded at all.
public protocol InferenceRuntime: Sendable {
    /// Drain outstanding device work before the process destroys the runtime.
    func synchronize()
    /// Caps the memory the allocator keeps for reuse between allocations. Takes effect at once.
    func setCacheLimit(bytes: Int)

    /// Caps what the allocator may hold in total, so a run that would page fails instead.
    func setMemoryLimit(bytes: Int)

    /// Caps what the allocator keeps wired — resident and neither compressed nor swapped —
    /// which is how a model that fits the GPU's working set stays in it. Never above what
    /// `gpuWorkingSetBytes()` reports; the runtime warns past that and the Mac pages.
    func setWiredLimit(bytes: Int)

    /// Bytes the GPU may keep resident: Metal's recommended working set, which
    /// `iogpu.wired_limit_mb` raises. Nil when there is no GPU runtime to ask.
    func gpuWorkingSetBytes() -> UInt64?

    /// What the last pass of a streamed layer stack read and how fast, or nil while nothing
    /// has streamed. What a settings readout shows beside "Streamed".
    func weightStreamReading() -> WeightStreamReading?

    /// One line naming the device and the memory it will work within, for logs and headers.
    func deviceSummary() -> String

    /// Memory use right now.
    func memorySnapshot() -> MemorySnapshot

    /// Decodes the VAE in overlapping tiles of `tile` latent cells a side, or exactly in one
    /// piece when `tile` is nil. Takes effect on the next decode; no reload is involved.
    func setVAETileSize(_ tile: Int?)

    /// The tile edge in force right now, or nil while the decode runs untiled. What a settings
    /// readout should show, and the only way to see what an environment variable set at launch
    /// left behind.
    func vaeTileSize() -> Int?
}

extension InferenceRuntime {
    /// A runtime with nothing to wire ignores the limit.
    public func setWiredLimit(bytes: Int) {}

    /// A runtime without a GPU has no working set to report.
    public func gpuWorkingSetBytes() -> UInt64? { nil }

    /// A runtime that never streams has nothing to report.
    public func weightStreamReading() -> WeightStreamReading? { nil }
}

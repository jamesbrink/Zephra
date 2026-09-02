/// The knobs and readouts of whatever GPU runtime a backend is built on.
///
/// Kept apart from `ImageGenerationBackend` on purpose: this is the process-wide allocator, not
/// one model, and the settings window needs it while no model is loaded at all.
public protocol InferenceRuntime: Sendable {
    /// Caps the memory the allocator keeps for reuse between allocations. Takes effect at once.
    func setCacheLimit(bytes: Int)

    /// Memory use right now.
    func memorySnapshot() -> MemorySnapshot
}

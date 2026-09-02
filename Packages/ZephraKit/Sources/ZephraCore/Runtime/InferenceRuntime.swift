/// The knobs and readouts of whatever GPU runtime a backend is built on.
///
/// Kept apart from `ImageGenerationBackend` on purpose: this is the process-wide allocator, not
/// one model, and the settings window needs it while no model is loaded at all.
public protocol InferenceRuntime: Sendable {
    /// Caps the memory the allocator keeps for reuse between allocations. Takes effect at once.
    func setCacheLimit(bytes: Int)

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

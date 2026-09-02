/// What the inference runtime's GPU allocator holds at one instant.
///
/// A plain value type so the UI can show live memory without knowing that MLX exists.
public struct MemorySnapshot: Sendable, Equatable {
    /// Bytes backing arrays that are still live.
    public let activeBytes: Int
    /// Bytes the allocator is holding for reuse rather than handing back to the system.
    public let cacheBytes: Int
    /// The high-water mark of active memory since the process started.
    public let peakBytes: Int

    public init(activeBytes: Int, cacheBytes: Int, peakBytes: Int) {
        self.activeBytes = activeBytes
        self.cacheBytes = cacheBytes
        self.peakBytes = peakBytes
    }

    /// A runtime that has not allocated anything.
    public static let zero = MemorySnapshot(activeBytes: 0, cacheBytes: 0, peakBytes: 0)
}

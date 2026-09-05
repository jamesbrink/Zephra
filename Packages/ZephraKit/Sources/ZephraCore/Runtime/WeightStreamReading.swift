/// What one pass of a streamed layer stack cost: the bytes read and how long they took.
///
/// A plain value type so the Performance tab and the benchmark can say "16.1 GB at 1.6 GB/s"
/// without knowing that MLX exists, and so a slow drive is diagnosed rather than guessed at.
public struct WeightStreamReading: Sendable, Equatable {
    /// Bytes of weights read from disk during the pass.
    public let bytes: Int
    /// How long the pass took, reads and compute together.
    public let seconds: Double

    public init(bytes: Int, seconds: Double) {
        self.bytes = bytes
        self.seconds = seconds
    }

    /// The pass's read rate, or zero for a pass that took no time.
    public var bytesPerSecond: Double {
        seconds > 0 ? Double(bytes) / seconds : 0
    }
}

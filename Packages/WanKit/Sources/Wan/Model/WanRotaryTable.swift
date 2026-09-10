import Foundation
import MLX
import ZephraMLX

/// The rotary angles of one clip's token grid, and the rotation they define.
///
/// Built once per clip shape and reused by every block of every step: the transformer keeps
/// the last table it built and asks for another only when the grid changes. `frequencies`
/// holds one cosine and one sine per token and pair, `[tokens, headDim / 2]`.
public struct WanRotaryTable {
    /// Tokens along time.
    public let frames: Int
    /// Tokens down the height.
    public let height: Int
    /// Tokens across the width.
    public let width: Int
    /// The angles, one per token and adjacent pair.
    public let frequencies: RotaryFrequencies

    public init(frames: Int, height: Int, width: Int, frequencies: RotaryFrequencies) {
        self.frames = frames
        self.height = height
        self.width = width
        self.frequencies = frequencies
    }

    /// Tokens the table covers.
    public var tokens: Int { frames * height * width }

    /// Whether this table was built for a grid of that shape.
    public func covers(frames: Int, height: Int, width: Int) -> Bool {
        self.frames == frames && self.height == height && self.width == width
    }

    /// Rotates `x`, `[batch, tokens, heads, headDim]`, pair by adjacent pair.
    ///
    /// Computed in float32 and cast back, as the reference's float32 table promotes a
    /// bfloat16 query before the result is written back in the query's dtype.
    public func rotate(_ x: MLXArray) -> MLXArray {
        frequencies.rotate(x, computeDType: .float32)
    }
}

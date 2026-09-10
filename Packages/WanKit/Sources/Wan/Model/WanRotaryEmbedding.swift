import Foundation
import MLX
import ZephraMLX

/// Wan's rotary embedding: one head's width split three ways, a log-spaced frequency ladder
/// per axis over integer token positions, applied to adjacent pairs of channels.
///
/// The reference (`WanRotaryPosEmbed`) gives height and width `2 * (headDim / 6)` channels
/// each and time what is left, 42, 42 and 44 of a 128-wide head; each axis carries the
/// `1 / theta^(2k / d)` ladder of a plain 1-D rotary embedding over that many channels, and a
/// token's angles are its frame index times the time ladder, then its row times the height
/// ladder, then its column times the width ladder. The pairing is adjacent channels, which is
/// `ZephraMLX.RotaryFrequencies`' convention, so the rotation itself is shared with the other
/// families; the ladders are built here in `Double`, as the reference builds its tables in
/// float64 and rounds once.
public struct WanRotaryEmbedding: Sendable, Hashable {
    /// Width of one head.
    public let headDim: Int
    /// Positions per axis the reference's tables cover; a grid longer than this on any axis
    /// is outside what the model was trained on.
    public let maxSeqLen: Int
    /// Ladders for the time, height and width axes, `channels / 2` entries each.
    public let ladders: [[Double]]

    /// Creates the embedding for a head `headDim` wide with the reference's split.
    public init(headDim: Int, maxSeqLen: Int, theta: Double = 10000) {
        self.headDim = headDim
        self.maxSeqLen = maxSeqLen
        let spatial = 2 * (headDim / 6)
        ladders = [headDim - 2 * spatial, spatial, spatial].map { channels in
            (0..<(channels / 2)).map { 1 / Foundation.pow(theta, Double(2 * $0) / Double(channels)) }
        }
    }

    /// The table for a grid of `frames` by `height` by `width` tokens, in frame, row, column
    /// order.
    public func table(frames: Int, height: Int, width: Int) -> WanRotaryTable {
        let axes = [frames, height, width]
        var cosines: [MLXArray] = []
        var sines: [MLXArray] = []
        for (axis, positions) in axes.enumerated() {
            let ladder = ladders[axis]
            var cosine: [Float] = []
            var sine: [Float] = []
            cosine.reserveCapacity(positions * ladder.count)
            sine.reserveCapacity(positions * ladder.count)
            for position in 0..<positions {
                for frequency in ladder {
                    let angle = Double(position) * frequency
                    cosine.append(Float(Foundation.cos(angle)))
                    sine.append(Float(Foundation.sin(angle)))
                }
            }
            // [positions, pairs] on this axis alone, broadcast over the other two.
            var shape = [1, 1, 1, ladder.count]
            shape[axis] = positions
            let full = [frames, height, width, ladder.count]
            cosines.append(MLX.broadcast(MLXArray(cosine, shape), to: full))
            sines.append(MLX.broadcast(MLXArray(sine, shape), to: full))
        }
        let tokens = frames * height * width
        return WanRotaryTable(
            frames: frames, height: height, width: width,
            frequencies: RotaryFrequencies(
                cos: MLX.concatenated(cosines, axis: -1).reshaped([tokens, -1]),
                sin: MLX.concatenated(sines, axis: -1).reshaped([tokens, -1])))
    }
}

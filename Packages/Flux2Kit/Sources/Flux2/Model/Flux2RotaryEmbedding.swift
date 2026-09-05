import Foundation
import MLX
import ZephraMLX

/// FLUX.2's four-axis rotary position embedding.
///
/// A head's width is split across four position axes, and every token carries an angle from
/// each, computed from its `Flux2PositionIDs` entry. Each axis contributes half its width in
/// angles, since rotation acts on adjacent pairs of channels, so the four halves add up to half
/// a head. Only the ladder differs from Qwen-Image's: the base is 2000 rather than 10000, so the
/// same distance turns the channels further.
///
/// The angles are built on the CPU in doubles and handed to MLX in one go, because a table is
/// built once per generation and read at every layer of every step.
public struct Flux2RotaryEmbedding: Sendable {
    /// Base of the frequency ladder.
    public let theta: Double
    /// How the head's width is divided between the four axes.
    public let axesDim: [Int]

    /// Creates an embedding for a model whose head is split as `axesDim`.
    public init(theta: Double = 2000, axesDim: [Int]) {
        self.theta = theta
        self.axesDim = axesDim
    }

    /// The table for one sequence: one row per id, in the order given.
    ///
    /// The transformer attends over text and image tokens as one sequence, text first, so the
    /// ids handed here are the text ids followed by the image ids, and the table's rows line up
    /// with that sequence.
    public func frequencies(ids: [[Int]]) -> RotaryFrequencies {
        precondition(ids.allSatisfy { $0.count == axesDim.count }, "each id needs one entry per axis")
        var angles: [Double] = []
        angles.reserveCapacity(ids.count * halfWidth)
        for id in ids {
            for (axis, dim) in axesDim.enumerated() {
                angles += self.angles(id[axis], dim: dim)
            }
        }
        return RotaryFrequencies(
            cos: MLXArray(angles.map { Float(Foundation.cos($0)) }, [ids.count, halfWidth]),
            sin: MLXArray(angles.map { Float(Foundation.sin($0)) }, [ids.count, halfWidth])
        )
    }

    /// Angles for one position on one axis: the position scaled down the frequency ladder.
    private func angles(_ position: Int, dim: Int) -> [Double] {
        (0..<(dim / 2)).map { index in
            Double(position) * pow(theta, -2 * Double(index) / Double(dim))
        }
    }

    /// Angles a token carries in total, which is half a head's width.
    private var halfWidth: Int { axesDim.reduce(0) { $0 + $1 / 2 } }
}

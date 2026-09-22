import Foundation
import MLX
import ZephraMLX

/// Qwen-Image 2.1's three-axis rotary position embedding.
///
/// A head's 128 channels are split `[16, 56, 56]` across the frame, row and column axes, and
/// each axis contributes half its width in angles, since rotation acts on **adjacent pairs** of
/// channels: 8 + 28 + 28 = 64 angles a token, which is half a head. That pairing is the
/// reference's `torch.view_as_complex` convention, and it is the one
/// `ZephraMLX.RotaryFrequencies.rotate` performs, which is why this builds one of those rather
/// than a table of its own.
///
/// **Theta is 10000 and is hard-coded**, not read from the configuration; only the text encoder
/// uses 5e6. The reference builds a 9216-row table — 0 to 8191 and then −1024 to −1, so a
/// negative index wraps onto its own position — and looks positions up in it. The angles here
/// are computed from the position instead, which is the same arithmetic without the wrap and
/// without a bound at 8191.
///
/// Angles are built on the CPU in doubles and handed to MLX in one go: a table is built once
/// per generation and read at every layer of every step.
public struct QwenImage21Rope: Sendable {
    /// The base of the frequency ladder. The transformer passes this and nothing else.
    public static let theta: Double = 10000

    /// Base of the frequency ladder.
    public let theta: Double
    /// How the head's width divides between frame, row and column.
    public let axesDim: [Int]

    /// Creates an embedding for a model whose head is split as `axesDim`.
    public init(theta: Double = QwenImage21Rope.theta, axesDim: [Int]) {
        self.theta = theta
        self.axesDim = axesDim
    }

    /// The table for one joint sequence: one row per token, in the sequence's own order.
    public func frequencies(_ positions: QwenImage21RopePositions) -> RotaryFrequencies {
        precondition(axesDim.count == 3, "2.1 splits a head across frame, row and column")
        let ladders = axesDim.map(ladder(_:))
        let halfWidth = ladders.reduce(0) { $0 + $1.count }

        var cosines = [Float]()
        var sines = [Float]()
        cosines.reserveCapacity(positions.count * halfWidth)
        sines.reserveCapacity(positions.count * halfWidth)
        for token in 0..<positions.count {
            let axes = [positions.frame[token], positions.height[token], positions.width[token]]
            for (axis, rungs) in ladders.enumerated() {
                for rung in rungs {
                    let angle = Double(axes[axis]) * rung
                    cosines.append(Float(Foundation.cos(angle)))
                    sines.append(Float(Foundation.sin(angle)))
                }
            }
        }
        return RotaryFrequencies(
            cos: MLXArray(cosines, [positions.count, halfWidth]),
            sin: MLXArray(sines, [positions.count, halfWidth]))
    }

    /// One axis's frequencies: `theta` raised to `-2i / dim`, one per rotated pair.
    private func ladder(_ dim: Int) -> [Double] {
        (0..<(dim / 2)).map { pow(theta, -2 * Double($0) / Double(dim)) }
    }
}

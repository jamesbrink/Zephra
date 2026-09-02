import Foundation
import MLX

/// Qwen-Image's multimodal rotary position embedding.
///
/// A head's width is split across three position axes — frame, height, width — and every token
/// carries an angle from each. Three details are load-bearing and none of them fails loudly:
///
/// 1. The spatial axes are **centred on zero**, not counted from it. A 64-cell row runs
///    -32 to -1 then 0 to 31, so the middle of the image sits at the origin and the model
///    generalises across sizes. This is what the reference calls `scale_rope`.
/// 2. Text tokens use **the same index on all three axes** — the diagonal that makes the scheme
///    "scalable" — and they start after the image, at `max(height / 2, width / 2)`, so a text
///    position can never collide with an image position.
/// 3. Rotation applies to **adjacent pairs** of a head's channels, so each axis contributes half
///    its width in angles, and the three halves must add up to half a head.
///
/// Get any of them wrong and the image is spatially incoherent rather than broken, which is why
/// this is written to be checked against the reference before anything is built on it.
public struct QwenImageRotaryEmbedding: Sendable {
    /// Base of the frequency ladder.
    public let theta: Double
    /// How the head's width is divided between frame, height, and width.
    public let axesDim: [Int]

    /// Creates an embedding for a model whose head is split as `axesDim`.
    public init(theta: Double = 10000, axesDim: [Int]) {
        self.theta = theta
        self.axesDim = axesDim
    }

    /// The tables for one generation: one row per image token, and one per text token.
    ///
    /// - Parameters:
    ///   - frames: Frames in the latent. A still image is one.
    ///   - height: Patch rows, which is latent height over the patch size.
    ///   - width: Patch columns.
    ///   - textLength: Tokens in the conditioning sequence.
    public func frequencies(frames: Int, height: Int, width: Int, textLength: Int)
        -> (image: RotaryFrequencies, text: RotaryFrequencies)
    {
        let framePositions = Array(0..<frames)
        let heightPositions = Self.centred(height)
        let widthPositions = Self.centred(width)

        var imageAngles: [Double] = []
        imageAngles.reserveCapacity(frames * height * width * halfWidth)
        // Row-major over frame, then row, then column: the order the packed tokens arrive in.
        for frame in framePositions {
            let frameAngles = angles(frame, dim: axesDim[0])
            for row in heightPositions {
                let rowAngles = angles(row, dim: axesDim[1])
                for column in widthPositions {
                    imageAngles += frameAngles
                    imageAngles += rowAngles
                    imageAngles += angles(column, dim: axesDim[2])
                }
            }
        }

        // Text sits past the image on every axis at once, so no text position shares a row with
        // an image position.
        let textOrigin = max(height / 2, width / 2)
        var textAngles: [Double] = []
        textAngles.reserveCapacity(textLength * halfWidth)
        for position in textOrigin..<(textOrigin + textLength) {
            for dim in axesDim {
                textAngles += angles(position, dim: dim)
            }
        }

        return (
            Self.table(imageAngles, rows: frames * height * width, columns: halfWidth),
            Self.table(textAngles, rows: textLength, columns: halfWidth)
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

    /// Positions along a spatial axis, centred on zero: the negative half, then the
    /// non-negative half. An odd length puts the extra position on the negative side, as the
    /// reference does.
    static func centred(_ count: Int) -> [Int] {
        let forward = count / 2
        return Array((-(count - forward))..<0) + Array(0..<forward)
    }

    private static func table(_ angles: [Double], rows: Int, columns: Int) -> RotaryFrequencies {
        RotaryFrequencies(
            cos: MLXArray(angles.map { Float(Foundation.cos($0)) }, [rows, columns]),
            sin: MLXArray(angles.map { Float(Foundation.sin($0)) }, [rows, columns])
        )
    }
}

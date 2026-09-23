import Foundation
import MLX

/// Qwen3-VL's interleaved multimodal rotary: three position axes sharing one ladder of
/// frequencies, and the **half-split** rotation.
///
/// Two things separate this from the transformer's own rotary, and taking either from the wrong
/// one compiles perfectly while rotating the wrong pairs. The channels are **interleaved**
/// rather than sectioned in blocks: with `mropeSection [24, 20, 20]` over the 64 half-dims, the
/// row axis takes 1, 4, …, 58, the column axis 2, 5, …, 59, and the time axis keeps everything
/// else — 0, 3, …, 57 and then 60 through 63, which is where its extra four come from. And the
/// rotation is `rotateHalf`, GPT-NeoX's convention, pairing channel `d` with `d + headDim/2`,
/// where the image transformer pairs adjacent channels. The two rotaries in this model do not
/// share code, and `ZephraMLX`'s shared `RotaryFrequencies.rotate` is the other one.
///
/// For a text-only prompt all three rows of `positions` carry the same index, so every channel
/// sees the same angle whatever axis it was given, and this collapses **exactly** to plain 1-D
/// rope with theta five million. `Qwen3VLRotaryTests` pins that equality rather than assuming
/// it, because it is what makes the general form safe to use on the text-only path too.
struct Qwen3VLRotary {
    /// Width of one attention head. Half of it is a frequency; the table is then doubled.
    let headDim: Int
    /// Inverse frequencies, `[headDim / 2]`, float32.
    private let inverseFrequencies: MLXArray
    /// Which of the three position rows each half-dim reads, `[headDim / 2]`, int32.
    private let axisOfHalfDim: MLXArray

    /// Builds the ladder for `headDim` channels at `theta`, split by `mropeSection`.
    init(headDim: Int, theta: Double, mropeSection: [Int]) {
        self.headDim = headDim
        let half = headDim / 2
        let exponents = (0..<half).map { Float(2 * $0) / Float(headDim) }
        inverseFrequencies = MLXArray(exponents.map { 1 / Float(pow(theta, Double($0))) })
        axisOfHalfDim = MLXArray(
            (0..<half).map { Int32(Self.axis(ofHalfDim: $0, mropeSection: mropeSection)) })
    }

    /// The axis half-dim `index` reads: 1 for rows, 2 for columns, 0 for time and the tail.
    ///
    /// The reference writes this as two slice assignments over a copy of the time row — H takes
    /// `slice(1, section[1] * 3, 3)` and W `slice(2, section[2] * 3, 3)` — so a half-dim past
    /// either slice's stop, which is the last four at the published section, stays time's.
    static func axis(ofHalfDim index: Int, mropeSection: [Int]) -> Int {
        guard mropeSection.count == 3 else { return 0 }
        if index % 3 == 1, index < mropeSection[1] * 3 { return 1 }
        if index % 3 == 2, index < mropeSection[2] * 3 { return 2 }
        return 0
    }

    /// The cosine and sine tables for `positions`, `[3, tokens]` of time, row and column
    /// indices, each `[tokens, headDim]` in `dtype`.
    ///
    /// The angles are computed in float32 whatever the stream's dtype, as the reference forces
    /// them to be: a bfloat16 position past a few thousand tokens is not the integer it was.
    func tables(positions: MLXArray, dtype: DType) -> (cos: MLXArray, sin: MLXArray) {
        let tokens = positions.dim(1)
        let half = headDim / 2
        let angles =
            positions.asType(.float32).expandedDimensions(axis: -1)
            * inverseFrequencies.reshaped(1, 1, half)
        let choice = MLX.broadcast(axisOfHalfDim.reshaped(1, 1, half), to: [1, tokens, half])
        let chosen = MLX.takeAlong(angles, choice, axis: 0).squeezed(axis: 0)
        let doubled = MLX.concatenated([chosen, chosen], axis: -1)
        return (MLX.cos(doubled).asType(dtype), MLX.sin(doubled).asType(dtype))
    }

    /// The positions a text-only prompt of `count` tokens carries: the same index on all three
    /// rows, which is what makes this rotary a plain 1-D one there.
    static func textPositions(count: Int) -> MLXArray {
        let run = MLXArray((0..<count).map { Int32($0) })
        return MLX.broadcast(run.reshaped(1, count), to: [3, count])
    }

    /// `rotate_half`: the second half of the channels negated and swapped in front of the first.
    static func rotateHalf(_ x: MLXArray) -> MLXArray {
        let half = x.dim(-1) / 2
        let front = x[.ellipsis, 0..<half]
        let back = x[.ellipsis, half...]
        return MLX.concatenated([-back, front], axis: -1)
    }

    /// `x` rotated by the tables, with `x` shaped `[batch, heads, tokens, headDim]`.
    static func applied(_ x: MLXArray, cos: MLXArray, sin: MLXArray) -> MLXArray {
        let broadcastable: [Int] = [1, 1, cos.dim(0), cos.dim(1)]
        return x * cos.reshaped(broadcastable) + rotateHalf(x) * sin.reshaped(broadcastable)
    }
}

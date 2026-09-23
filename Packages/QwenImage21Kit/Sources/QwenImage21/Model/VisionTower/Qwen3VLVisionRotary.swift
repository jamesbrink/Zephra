import Foundation
import MLX

/// The tower's own rotary: axial 2-D over the patch grid, half the head width to each axis.
///
/// The head is 72 wide (1152 over 16 heads), so the spatial dimension is 36 and there are 18
/// inverse frequencies. The row angles and the column angles are concatenated to 36 and that is
/// doubled to 72, then applied with `rotateHalf` — the same convention the decoder uses and the
/// opposite of the image transformer's.
///
/// **The theta is in no shipped configuration file.** `vision_config` in
/// `text_encoder/config.json` carries no `rope_theta` and no `rope_parameters`, so transformers
/// fills in its own default, and the buffer it computes is `persistent=False` and therefore in
/// none of the 750 published tensors either. The number is **10,000** — not the decoder's five
/// million — and it is written down here and pinned by `vision.safetensors`'s `rope.real.theta`
/// and `rope.real.invFreq`, dumped from `Qwen3VLVisionRotaryEmbedding` against the release's own
/// vision config. Guessing it would rotate every reference picture's patches by the wrong
/// angles, which is a plausible picture of a different reference.
struct Qwen3VLVisionRotary {
    /// What transformers supplies for a vision config that names no theta.
    static let theta: Double = 10_000

    private let inverseFrequencies: MLXArray
    private let mergeSize: Int

    init(_ configuration: Qwen3VLTextConfiguration.Vision) {
        let spatial = configuration.headDim / 2
        let exponents = stride(from: 0, to: spatial, by: 2).map { Float($0) / Float(spatial) }
        inverseFrequencies = MLXArray(exponents.map { 1 / Float(pow(Self.theta, Double($0))) })
        mergeSize = configuration.spatialMergeSize
    }

    /// The cosine and sine tables for every patch of `grid`, each `[patches, headDim]`.
    func tables(for grid: Qwen3VLImageGrid, dtype: DType) -> (cos: MLXArray, sin: MLXArray) {
        let coordinates = Qwen3VLPatchOrder.frameRepeated(grid, mergeSize: mergeSize)
        let rows = MLXArray(coordinates.map { Float($0.row) })
        let columns = MLXArray(coordinates.map { Float($0.column) })
        let frequencies = inverseFrequencies.reshaped(1, -1)
        let spatial = MLX.concatenated(
            [
                rows.reshaped(-1, 1) * frequencies,
                columns.reshaped(-1, 1) * frequencies,
            ], axis: -1)
        let doubled = MLX.concatenated([spatial, spatial], axis: -1)
        return (MLX.cos(doubled).asType(dtype), MLX.sin(doubled).asType(dtype))
    }

    /// `x` rotated by the tables, with `x` shaped `[patches, heads, headDim]`.
    ///
    /// The tables carry no head axis, so they are unsqueezed in front of it — the reference's
    /// `cos.unsqueeze(-2)` — rather than in front of the sequence as the decoder's are.
    static func applied(_ x: MLXArray, cos: MLXArray, sin: MLXArray) -> MLXArray {
        let table: [Int] = [cos.dim(0), 1, cos.dim(1)]
        return x * cos.reshaped(table) + Qwen3VLRotary.rotateHalf(x) * sin.reshaped(table)
    }
}

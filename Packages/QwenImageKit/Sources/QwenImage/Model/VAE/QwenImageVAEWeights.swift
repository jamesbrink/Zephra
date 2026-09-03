import Foundation
import MLX

/// Converts the published VAE weights into the shapes this decoder uses.
///
/// Two conversions, both mechanical.
///
/// **Time is dropped.** The autoencoder is a video model: its convolutions are 3-D and causal,
/// front-padding the time axis by two and reading a kernel three deep. A still image is a single
/// frame, so those two padded positions are always zero and only the **last** temporal slice of
/// the kernel ever multiplies real data. Taking that slice is exact, not an approximation, and
/// it turns every 3-D convolution into the 2-D convolution it actually performs here — no 5-D
/// tensors, no `Conv3d`, and a good deal less memory during the decode.
///
/// **Layout is transposed.** PyTorch stores a convolution kernel as `[out, in, h, w]` and MLX as
/// `[out, h, w, in]`.
enum QwenImageVAEWeights {
    /// The decoder's weights, sliced and transposed for this module tree.
    static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { converted, entry in
            let (key, value) = entry
            guard key.hasSuffix(".weight") else {
                converted[key] = value
                return
            }
            switch value.ndim {
            case 5:
                // [out, in, depth, h, w] -> the last depth slice -> [out, h, w, in].
                let planar = value[0..., 0..., value.shape[2] - 1]
                converted[key] = planar.transposed(0, 2, 3, 1)
            case 4:
                converted[key] = value.transposed(0, 2, 3, 1)
            default:
                converted[key] = value
            }
        }
    }
}

import Foundation
import MLX

/// The decoder's only normalisation: each location divided by the root mean square of its own
/// channels. It carries no weights, so it is a function and not a module, and a checkpoint has
/// nothing to say about it.
///
/// `norm_layer: "pixel_norm"` in the official configurator, `PerChannelRMSNorm` in diffusers.
/// The epsilon is the reference's 1e-8, not the 1e-6 the residual blocks are configured with:
/// that value only reaches the LayerNorm a width-changing shortcut would have, and this decoder
/// changes width in its upsamplers, never in a block.
enum LTX2PixelNorm {
    static let epsilon: Float = 1e-8

    /// `x / sqrt(mean(x², channels) + eps)` over the last axis.
    static func apply(_ x: MLXArray) -> MLXArray {
        x * MLX.rsqrt(MLX.mean(x * x, axis: -1, keepDims: true) + epsilon)
    }
}

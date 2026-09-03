import Foundation
import MLX

/// Converts the published VAE weights into the shapes this autoencoder uses.
///
/// Two conversions, both mechanical. PyTorch stores a convolution kernel as `[out, in, h, w]`
/// and MLX as `[out, h, w, in]`, so every 4-D weight is transposed. And the mid-block
/// attention's output projection sits in a `Sequential` with a dropout, so the checkpoint
/// names it `to_out.0`; it is renamed to `to_out` for the reason `Flux2TransformerWeights`
/// records.
///
/// The batch-norm's `num_batches_tracked` is a bookkeeping integer with no bearing on the
/// output, and it is dropped here rather than filtered later so that the intent is written down.
enum Flux2VAEWeights {
    /// The autoencoder's weights, transposed and renamed for this module tree.
    static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { converted, entry in
            let (key, value) = entry
            guard !key.hasSuffix("num_batches_tracked") else { return }
            let name = key.replacingOccurrences(of: ".to_out.0.", with: ".to_out.")
            if key.hasSuffix(".weight"), value.ndim == 4 {
                converted[name] = value.transposed(0, 2, 3, 1)
            } else {
                converted[name] = value
            }
        }
    }
}

import Foundation
import MLX

/// The checkpoint's tensors in the layouts the module tree holds them in.
///
/// Every name is kept: the tree's parameter paths are the checkpoint's keys,
/// `encoder.conv_in.weight` and `decoder.up_blocks.0.upsampler.resample.1.weight` alike -- the
/// numbered `Sequential` included, since the tree spells `resample` as a pair and MLX numbers
/// the halves the same way. What changes is the layout, because the tree is channels-last and
/// the checkpoint is PyTorch's: a kernel goes from `[out, in, kh, kw]` to MLX's
/// `[out, kh, kw, in]`, and a norm's gain from the broadcastable `[dim, 1, 1, 1]` (or
/// `[dim, 1, 1]` in the attention block) to a flat `[dim]`. Biases are already flat.
///
/// **Twelve tensors are dropped**, the six `time_conv` modules' weights and biases. They are
/// unreachable for a still image -- `QwenImage21CausalConv` states why in full -- so the tree
/// does not build those modules and would refuse to be loaded from a dictionary that still
/// named them. `WeightKeyCoverageTests` claims them by name rather than letting them go
/// unlisted, so dropping them is a decision the suite states and not an omission.
///
/// `checkpointShape` is the inverse, for a suite that checks the tree against a file's header
/// without reading a weight.
public enum QwenImage21VAEWeights {
    /// The infix every unreachable temporal convolution's key carries.
    public static let temporalInfix = ".time_conv."

    /// `weights` under the same names, in the tree's layouts, less the temporal convolutions.
    public static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { converted, entry in
            guard !entry.key.contains(temporalInfix) else { return }
            converted[entry.key] = treeLayout(of: entry.value, named: entry.key)
        }
    }

    /// One tensor in the tree's layout, decided by its name and rank.
    static func treeLayout(of tensor: MLXArray, named name: String) -> MLXArray {
        if name.hasSuffix(".gamma") {
            return tensor.reshaped([-1])
        }
        return tensor.ndim == 4 ? tensor.transposed(0, 2, 3, 1) : tensor
    }

    /// The shape the checkpoint holds the parameter at `path` in, given the tree's `shape`.
    public static func checkpointShape(of path: String, _ shape: [Int]) -> [Int] {
        if path.hasSuffix(".gamma") {
            return shape + (path.contains(".attentions.") ? [1, 1] : [1, 1, 1])
        }
        return shape.count == 4 ? [shape[0], shape[3], shape[1], shape[2]] : shape
    }
}

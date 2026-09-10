import Foundation
import MLX

/// The checkpoint's tensors in the layouts the module tree holds them in.
///
/// Every name is kept: the tree's parameter paths are the checkpoint's keys, `encoder.conv_in.
/// weight` and `decoder.up_blocks.0.upsampler.resample.1.weight` alike. What changes is the
/// layout, because the tree is channels-last and the checkpoint is PyTorch's: a 3-D kernel
/// goes from `[out, in, kt, kh, kw]` to MLX's `[out, kt, kh, kw, in]`, a 2-D one from
/// `[out, in, kh, kw]` to `[out, kh, kw, in]`, and a norm's gain from the broadcastable
/// `[dim, 1, 1, 1]` (or `[dim, 1, 1]` in the attention block) to a flat `[dim]`. Biases are
/// already flat. `checkpointShape` is the inverse, for a test that checks the tree against a
/// file's header without reading a weight.
public enum WanVAEWeights {
    /// `weights` under the same names, in the tree's layouts.
    public static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { converted, entry in
            converted[entry.key] = treeLayout(of: entry.value, named: entry.key)
        }
    }

    /// One tensor in the tree's layout, decided by its name and rank.
    static func treeLayout(of tensor: MLXArray, named name: String) -> MLXArray {
        if name.hasSuffix(".gamma") {
            return tensor.reshaped([-1])
        }
        switch tensor.ndim {
        case 5: return tensor.transposed(0, 2, 3, 4, 1)
        case 4: return tensor.transposed(0, 2, 3, 1)
        default: return tensor
        }
    }

    /// The shape the checkpoint holds the parameter at `path` in, given the tree's `shape`.
    public static func checkpointShape(of path: String, _ shape: [Int]) -> [Int] {
        if path.hasSuffix(".gamma") {
            return shape + (path.contains(".attentions.") ? [1, 1] : [1, 1, 1])
        }
        switch shape.count {
        case 5: return [shape[0], shape[4], shape[1], shape[2], shape[3]]
        case 4: return [shape[0], shape[3], shape[1], shape[2]]
        default: return shape
        }
    }
}

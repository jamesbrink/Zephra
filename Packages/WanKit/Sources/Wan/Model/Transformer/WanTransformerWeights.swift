import Foundation
import MLX

/// The checkpoint's tensor names against this module tree's paths.
///
/// The tree spells almost every tensor as the release does, so the packed variant, which keeps
/// the release's names, loads by name. Three paths the tree cannot spell are lists in the
/// reference: the attention's output projection is `to_out.0`, the feed-forward's two linears
/// `net.0.proj` and `net.2`; they are `to_out`, `proj_in` and `proj_out` here, and this is the
/// one place the two spellings meet, for the loader on the way in and for the quantization
/// manifest and the weight stream, which know tensors by the checkpoint's names, on the way
/// back.
///
/// One tensor changes shape rather than name: `patch_embedding.weight` is stored the way
/// PyTorch stores a convolution, `[out, in, kd, kh, kw]`, and MLX's convolution wants
/// `[out, kd, kh, kw, in]`. `sanitized` turns it round when it arrives in PyTorch's order,
/// which is told by the channels being on axis 1 rather than last: a patch is one or two
/// cells on a side and the channels are eight at the smallest, so the two orders never look
/// alike.
public enum WanTransformerWeights {
    /// The renames, as (the checkpoint's infix, the tree's).
    static let renames = [
        (".to_out.0.", ".to_out."),
        (".ffn.net.0.proj.", ".ffn.proj_in."),
        (".ffn.net.2.", ".ffn.proj_out."),
    ]
    static let patchKernel = "patch_embedding.weight"

    /// The checkpoint's tensors under the names and in the layout this module tree uses.
    public static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { renamed, entry in
            let value =
                entry.key == patchKernel && isTorchKernel(entry.value)
                ? WanPatchEmbedding.kernel(fromTorch: entry.value) : entry.value
            renamed[moduleName(of: entry.key)] = value
        }
    }

    /// One checkpoint name under the name this module tree uses.
    public static func moduleName(of key: String) -> String {
        var padded = "." + key
        for (checkpoint, module) in renames {
            padded = padded.replacingOccurrences(of: checkpoint, with: module)
        }
        return String(padded.dropFirst())
    }

    /// A module path back under the name the checkpoint and its manifest know it by.
    public static func checkpointName(of path: String) -> String {
        var padded = "." + path
        for (checkpoint, module) in renames {
            padded = padded.replacingOccurrences(of: module, with: checkpoint)
        }
        return String(padded.dropFirst())
    }

    /// Whether a five-axis kernel has its channels on axis 1, PyTorch's order.
    static func isTorchKernel(_ weight: MLXArray) -> Bool {
        weight.ndim == 5 && weight.shape[4] < weight.shape[1]
    }
}

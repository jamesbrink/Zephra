import Foundation
import MLX

/// The checkpoint's names for the vision tower against this module tree's paths.
///
/// The release spells every tower tensor `model.visual.<path>`, and the tree's paths are that
/// suffix exactly, so the mapping is one prefix on and off. One tensor changes **shape**:
/// `patch_embed.proj.weight` is stored as PyTorch stores a `Conv3d`, `[1152, 3, 2, 16, 16]`,
/// and the port runs that convolution as a linear over its own flattened receptive field, so
/// it arrives as `[1152, 1536]`. Nothing is transposed — the axis order `(channel, frame, row,
/// column)` is already the order the preprocessing lays a patch vector out in, which is why
/// this is a reshape and not a permute.
public enum Qwen3VLVisionWeights {
    /// The prefix the release puts on every tower tensor.
    public static let prefix = "model.visual."

    /// The one tensor whose stored shape is not the tree's.
    public static let patchKernel = "patch_embed.proj.weight"

    /// `weights` under the tree's paths, the kernel flattened, everything else untouched.
    public static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { kept, entry in
            guard entry.key.hasPrefix(prefix) else { return }
            let path = String(entry.key.dropFirst(prefix.count))
            kept[path] =
                path == patchKernel && entry.value.ndim == 5
                ? entry.value.reshaped(entry.value.dim(0), -1) : entry.value
        }
    }

    /// The checkpoint's name for a module path.
    public static func checkpointName(of path: String) -> String { prefix + path }

    /// Every key the tower loads, given its configuration.
    ///
    /// Written out rather than read back off a built tree, for the reason
    /// `Qwen3VLTextWeights.expectedKeys` is: a tree wrong in the same way as the expectation
    /// would agree with itself.
    public static func expectedKeys(_ configuration: Qwen3VLTextConfiguration.Vision) -> Set<String>
    {
        var keys: Set<String> = [
            prefix + patchKernel, prefix + "patch_embed.proj.bias", prefix + "pos_embed.weight",
        ]
        for block in 0..<configuration.depth { keys.formUnion(blockKeys(block)) }
        keys.formUnion(mergerKeys(prefix + "merger"))
        for merger in configuration.deepstackVisualIndexes.indices {
            keys.formUnion(mergerKeys("\(prefix)deepstack_merger_list.\(merger)"))
        }
        return keys
    }

    /// One block's twelve tensors. Every linear here carries a bias, unlike the decoder's.
    public static func blockKeys(_ block: Int) -> [String] {
        let base = "\(prefix)blocks.\(block)"
        return ["norm1", "norm2", "attn.qkv", "attn.proj", "mlp.linear_fc1", "mlp.linear_fc2"]
            .flatMap { ["\(base).\($0).weight", "\(base).\($0).bias"] }
    }

    /// A merger's six: a `LayerNorm` and two `Linear`s, all with biases.
    public static func mergerKeys(_ base: String) -> [String] {
        ["norm", "linear_fc1", "linear_fc2"].flatMap { ["\(base).\($0).weight", "\(base).\($0).bias"] }
    }
}

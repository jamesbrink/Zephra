import Foundation
import MLX

/// Converts the published autoencoder weights into the names these module trees use, and back.
///
/// One conversion each, and a small one: the pack prefixes every tensor with the file it came
/// from rather than a module, `vae_decoder.` or `vae_encoder.`, and each tree starts at
/// `conv_in`. The two halves ship as two files but are packed into one `vae` component, so a
/// loader may hold both at once — which is why each sanitizer drops what is not under its own
/// prefix rather than assuming it was handed one file. Kernels are already
/// `[out, kd, kh, kw, in]`, MLX's own order, so nothing is transposed; a fixture dumped from
/// PyTorch is written in that order too, so one loader serves both.
///
/// The encoder's two statistics are the one real rename. The pack calls them
/// `_mean_of_means` and `_std_of_means`, leading underscores and all, because the official
/// checkpoint registers them as buffers with those names — and mlx-swift's parameter filter
/// drops any key that begins with an underscore, so a tree that spelled them that way would
/// load them and then leave them out of `parameters()`, out of anything that walks the tree,
/// and out of the key check that is supposed to notice. The tree names them without, and
/// `encoderCheckpointName(of:)` puts the underscore back for anything asking what the file
/// calls a path.
public enum LTX2VAEWeights {
    /// The prefix every tensor of the pack's decoder file carries.
    public static let prefix = "vae_decoder."
    /// The prefix every tensor of the pack's encoder file carries.
    public static let encoderPrefix = "vae_encoder."

    /// The encoder paths the pack spells differently, as (the file's name, the tree's).
    static let encoderRenames = [
        ("per_channel_statistics._mean_of_means", "per_channel_statistics.mean_of_means"),
        ("per_channel_statistics._std_of_means", "per_channel_statistics.std_of_means"),
    ]

    /// The decoder's weights, renamed for its module tree.
    public static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        stripped(weights, of: prefix)
    }

    /// The encoder's weights, renamed for its module tree.
    public static func sanitizedEncoder(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        stripped(weights, of: encoderPrefix).reduce(into: [:]) { renamed, entry in
            let path = encoderRenames.first { $0.0 == entry.key }?.1 ?? entry.key
            renamed[path] = entry.value
        }
    }

    /// What the pack's encoder file calls the parameter at `path` in the module tree.
    public static func encoderCheckpointName(of path: String) -> String {
        encoderPrefix + (encoderRenames.first { $0.1 == path }?.0 ?? path)
    }

    /// `weights` under `prefix`, with it removed; anything under another prefix is dropped.
    static func stripped(_ weights: [String: MLXArray], of prefix: String) -> [String: MLXArray] {
        weights.reduce(into: [:]) { converted, entry in
            guard entry.key.hasPrefix(prefix) else { return }
            converted[String(entry.key.dropFirst(prefix.count))] = entry.value
        }
    }
}

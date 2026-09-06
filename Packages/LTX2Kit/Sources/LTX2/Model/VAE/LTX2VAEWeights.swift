import Foundation
import MLX

/// Converts the published decoder weights into the names this module tree uses.
///
/// One conversion, and a small one: the pack prefixes every tensor with `vae_decoder.`, which
/// names the file it came from rather than a module, and the tree starts at `conv_in`. Kernels
/// are already `[out, kd, kh, kw, in]`, MLX's own order, so nothing is transposed; a fixture
/// dumped from PyTorch is written in that order too, so one loader serves both.
public enum LTX2VAEWeights {
    /// The prefix every tensor of the pack's decoder file carries.
    public static let prefix = "vae_decoder."

    /// The decoder's weights, renamed for this module tree. Tensors under any other prefix --
    /// the pack's own encoder, were it ever loaded from the same dictionary -- are dropped.
    public static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { converted, entry in
            guard entry.key.hasPrefix(prefix) else { return }
            converted[String(entry.key.dropFirst(prefix.count))] = entry.value
        }
    }
}

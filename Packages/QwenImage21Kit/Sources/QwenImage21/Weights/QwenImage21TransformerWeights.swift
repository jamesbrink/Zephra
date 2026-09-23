import Foundation
import MLX

/// Renames the two checkpoint paths that number a child by its position.
///
/// | checkpoint | module tree |
/// | --- | --- |
/// | `modulation.1.` | `modulation.projection.` |
/// | `attn.to_out.0.` | `attn.to_out.` |
///
/// The reference wraps the modulation linear in a `Sequential` behind a `SiLU` and a block's
/// attention output in a `ModuleList` with a dropout, so both weights are named by their index.
///
/// Mirroring the number in the module tree does not work, and the reason is worth recording:
/// MLX rebuilds a numeric path segment as an **array** position when it unflattens weights, and
/// as a **dictionary** key when it replaces modules. A tree shaped for one cannot be used by the
/// other, so a model with numbered children can be loaded or quantized but not both.
public enum QwenImage21TransformerWeights {
    private static let renames = [
        (checkpoint: "modulation.1.", module: "modulation.projection."),
        (checkpoint: ".attn.to_out.0.", module: ".attn.to_out."),
    ]

    /// A module path back under the name the manifest and the shards know it by.
    public static func checkpointName(of path: String) -> String {
        rewrite(path) { $0.module } to: { $0.checkpoint }
    }

    /// One checkpoint path under the name this module tree uses.
    public static func moduleName(of key: String) -> String {
        rewrite(key) { $0.checkpoint } to: { $0.module }
    }

    /// The checkpoint's tensors under the names this module tree uses.
    public static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { renamed, entry in
            renamed[moduleName(of: entry.key)] = entry.value
        }
    }

    /// Both renames are anchored — one on the front of the path, one on a dot either side — so
    /// bounding the string with dots lets a single replacement do either.
    private static func rewrite(
        _ path: String,
        _ from: ((checkpoint: String, module: String)) -> String,
        to: ((checkpoint: String, module: String)) -> String
    ) -> String {
        var bounded = "." + path + "."
        for rename in renames {
            bounded = bounded.replacingOccurrences(
                of: anchored(from(rename)), with: anchored(to(rename)))
        }
        return String(bounded.dropFirst().dropLast())
    }

    /// A rename that already begins with a dot matches anywhere; one that does not is a prefix,
    /// and the bounding dot is what pins it there.
    private static func anchored(_ fragment: String) -> String {
        fragment.hasPrefix(".") ? fragment : "." + fragment
    }
}

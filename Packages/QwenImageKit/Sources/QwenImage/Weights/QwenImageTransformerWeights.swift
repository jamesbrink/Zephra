import Foundation
import MLX

/// Renames the three checkpoint paths that number a layer by its position.
///
/// The reference wraps three things in `Sequential` — modulation behind a SiLU, the
/// feed-forward around a dropout, and the image stream's output before another dropout — so the
/// checkpoint names their weights `img_mod.1`, `net.0.proj`, `net.2`, and `to_out.0`.
///
/// Mirroring those numbers in the module tree does not work, and the reason is worth recording:
/// MLX rebuilds a numeric path segment as an **array** position when it unflattens weights, and
/// as a **dictionary** key when it replaces modules. A tree shaped for one cannot be used by the
/// other, so a model with numbered children can be loaded or quantized but not both. Renaming
/// four prefixes here costs less than that, and `weightNamesLineUp` checks that nothing is left
/// behind on either side.
enum QwenImageTransformerWeights {
    /// The rename, longest prefix first so `net.0.proj` is matched before `net.0`.
    private static let renames = [
        (".img_mod.1.", ".img_mod.projection."),
        (".txt_mod.1.", ".txt_mod.projection."),
        (".net.0.proj.", ".input."),
        (".net.2.", ".output."),
        (".to_out.0.", ".to_out."),
    ]

    /// A module path back under the name the manifest knows it by, which is the checkpoint's.
    static func checkpointName(of path: String) -> String {
        var name = "." + path + "."
        for (from, to) in renames where name.contains(to) {
            name = name.replacingOccurrences(of: to, with: from)
            break
        }
        return String(name.dropFirst().dropLast())
    }

    /// The checkpoint's tensors under the names this module tree uses.
    static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { renamed, entry in
            renamed[moduleName(of: entry.key)] = entry.value
        }
    }

    /// One checkpoint path under the name this module tree uses.
    static func moduleName(of key: String) -> String {
        // Bounded by dots at both ends, so a prefix at the very start of a key matches too --
        // which is what a block's own weights look like when a block is loaded on its own.
        var bounded = "." + key + "."
        for (from, to) in renames where bounded.contains(from) {
            bounded = bounded.replacingOccurrences(of: from, with: to)
            break
        }
        return String(bounded.dropFirst().dropLast())
    }
}

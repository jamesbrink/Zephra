import Foundation
import MLX

/// Renames the one checkpoint path that numbers a layer by its position.
///
/// The reference wraps the dual-stream block's image output in a `Sequential` with a dropout,
/// so the checkpoint names that weight `attn.to_out.0`. The single-stream block's output has no
/// such wrapper and is `attn.to_out` already, which is why the rename is confined to the
/// dual-stream blocks rather than applied by suffix.
///
/// Mirroring the number in the module tree does not work, and the reason is worth recording:
/// MLX rebuilds a numeric path segment as an **array** position when it unflattens weights, and
/// as a **dictionary** key when it replaces modules. A tree shaped for one cannot be used by the
/// other, so a model with numbered children can be loaded or quantized but not both.
enum Flux2TransformerWeights {
    private static let dualStreamPrefix = "transformer_blocks."
    private static let checkpointForm = ".attn.to_out.0."
    private static let moduleForm = ".attn.to_out."

    /// A module path back under the name the manifest knows it by, which is the checkpoint's.
    static func checkpointName(of path: String) -> String {
        guard path.hasPrefix(dualStreamPrefix) else { return path }
        let bounded = ("." + path + ".").replacingOccurrences(of: moduleForm, with: checkpointForm)
        return String(bounded.dropFirst().dropLast())
    }

    /// The checkpoint's tensors under the names this module tree uses.
    static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { renamed, entry in
            renamed[moduleName(of: entry.key)] = entry.value
        }
    }

    /// One checkpoint path under the name this module tree uses.
    static func moduleName(of key: String) -> String {
        guard key.hasPrefix(dualStreamPrefix) else { return key }
        let bounded = ("." + key + ".").replacingOccurrences(of: checkpointForm, with: moduleForm)
        return String(bounded.dropFirst().dropLast())
    }
}

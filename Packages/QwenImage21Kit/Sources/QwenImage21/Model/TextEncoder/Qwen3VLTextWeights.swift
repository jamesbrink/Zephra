import Foundation
import MLX

/// The checkpoint's names for the decoder stack against this module tree's paths.
///
/// The release spells every decoder tensor `model.language_model.<path>`, and the tree's paths
/// are that suffix exactly, so the mapping is one prefix on and off. Nothing changes shape.
///
/// Two published tensors are **omitted on purpose** and are the reason this type exists rather
/// than a `String.dropFirst` at the call site:
///
/// - `model.language_model.norm.weight` — the transformer reads the last layer's output before
///   this norm, so it is never applied and never loaded. `Qwen3VLLanguageModel` says why.
/// - `lm_head.weight` — 622 million parameters and 1.24 GB. `tie_word_embeddings` is false and
///   the tensor **does** exist in the shards, so a pack has to exclude it explicitly rather
///   than assume it away, and a coverage test that did not name it would read its absence from
///   the tree as a fault.
public enum Qwen3VLTextWeights {
    /// The prefix the release puts on every decoder tensor.
    public static let prefix = "model.language_model."

    /// The prefix the release puts on the other model in the same component, the vision tower.
    ///
    /// Stated here so a coverage test can say "everything else under the tower's prefix" about
    /// one shared index without naming the tower's own type.
    public static let towerPrefix = "model.visual."

    /// The checkpoint keys this port deliberately does not load.
    public static let omitted: Set<String> = ["model.language_model.norm.weight", "lm_head.weight"]

    /// `weights` under the tree's paths, with the omitted keys and everything under another
    /// prefix — the tower's — dropped.
    public static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { kept, entry in
            guard !omitted.contains(entry.key), entry.key.hasPrefix(prefix) else { return }
            kept[String(entry.key.dropFirst(prefix.count))] = entry.value
        }
    }

    /// The checkpoint's name for a module path, which is what a manifest and a weight stream
    /// know a tensor by.
    public static func checkpointName(of path: String) -> String { prefix + path }

    /// Every key the decoder stack loads, for a stack `layers` deep over `vocabulary` rows.
    ///
    /// Written out rather than read back off a built tree: a tree that is wrong in the same way
    /// as the expectation would agree with itself.
    public static func expectedKeys(layers: Int) -> Set<String> {
        var keys: Set<String> = [prefix + "embed_tokens.weight"]
        for layer in 0..<layers { keys.formUnion(layerKeys(layer)) }
        return keys
    }

    /// One layer's eleven tensors. Every one is a weight; this stack has no biases at all.
    public static func layerKeys(_ layer: Int) -> [String] {
        let base = "\(prefix)layers.\(layer)"
        return [
            "\(base).input_layernorm.weight",
            "\(base).post_attention_layernorm.weight",
            "\(base).mlp.gate_proj.weight",
            "\(base).mlp.up_proj.weight",
            "\(base).mlp.down_proj.weight",
            "\(base).self_attn.q_proj.weight",
            "\(base).self_attn.k_proj.weight",
            "\(base).self_attn.v_proj.weight",
            "\(base).self_attn.o_proj.weight",
            // The two that say Qwen3 rather than Qwen2.5, which biases the projections above
            // and norms nothing per head.
            "\(base).self_attn.q_norm.weight",
            "\(base).self_attn.k_norm.weight",
        ]
    }
}

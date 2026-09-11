import Foundation
import MLX

/// The pack's tensor names against this module tree's paths.
///
/// The `mlx-community` pack already names the video lane the way the tree does — `attn1.to_out`
/// rather than `to_out.0`, `ff.proj_in` rather than `net.0.proj` — so two things remain. Every
/// key carries a `transformer.` prefix, which goes. And the timestep embedders sit under
/// `emb.timestep_embedder.linear1`, one level deeper than `LTX2AdaLayerNormSingle` nests them,
/// so that level is folded away on the way in and put back by `checkpointName(of:)` on the way
/// to the quantization manifest, which knows tensors by the pack's names.
///
/// Audio-lane tensors are dropped unless the tree has the lane (`sanitized(_:audio:)`), and
/// mapped one level down when it has: the pack keeps them flat beside the video lane's,
/// `transformer_blocks.N.audio_attn1` and `av_ca_a2v_gate_adaln_single`, where the tree holds
/// them under `transformer_blocks.N.audio.` and `audio.`; `moduleName(of:)` puts the level
/// in and `checkpointName(of:)` takes it out again.
public enum LTX2TransformerWeights {
    static let prefix = "transformer."
    private static let checkpointForm = ".emb.timestep_embedder."
    private static let moduleForm = ".emb."

    /// The name fragments that mark a tensor as the audio lane's, or the cross-modal attention
    /// that only runs with one. `LTX2QuantizationPlan.audioOmitted` in the backend package
    /// says the same words in its own patterns (`av_ca` there as a prefix under
    /// `transformer.`); `WeightKeyCoverageTests` is what keeps the two agreeing.
    public static let audioMarkers = ["audio", "a2v", "v2a", "av_ca"]

    /// Whether `key` belongs to the audio lane.
    public static func isAudio(_ key: String) -> Bool {
        audioMarkers.contains { key.contains($0) }
    }

    /// The pack's tensors under the names this module tree uses: the video lane's, and the
    /// audio lane's too when `audio` says the tree has one.
    public static func sanitized(_ weights: [String: MLXArray], audio: Bool = false) -> [String: MLXArray] {
        weights.reduce(into: [:]) { renamed, entry in
            guard audio || !isAudio(entry.key) else { return }
            renamed[moduleName(of: entry.key)] = entry.value
        }
    }

    /// One pack path under the name this module tree uses.
    public static func moduleName(of key: String) -> String {
        let bare = key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key
        let folded = ("." + bare).replacingOccurrences(of: checkpointForm, with: moduleForm).dropFirst().description
        guard isAudio(folded) else { return folded }
        return nested(folded)
    }

    /// A module path back under the name the pack and its manifest know it by.
    public static func checkpointName(of path: String) -> String {
        let flat = path.replacingOccurrences(of: ".audio.", with: ".").replacingOccurrences(of: "^audio\\.", with: "", options: .regularExpression)
        return prefix + ("." + flat).replacingOccurrences(of: moduleForm, with: checkpointForm).dropFirst()
    }

    /// An audio-lane path with the tree's `audio.` level put in: after `transformer_blocks.N.`
    /// for a block's tensor, in front for the transformer's own.
    static func nested(_ path: String) -> String {
        let block = "transformer_blocks."
        guard path.hasPrefix(block), let dot = path.dropFirst(block.count).firstIndex(of: ".") else {
            return "audio." + path
        }
        let head = path[path.startIndex...dot]
        return head + "audio." + path[path.index(after: dot)...]
    }
}

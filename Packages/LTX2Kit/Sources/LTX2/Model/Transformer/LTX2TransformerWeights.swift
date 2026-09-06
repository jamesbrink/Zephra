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
/// Audio-lane tensors are dropped rather than mapped: a video-only pack has none, and a full
/// pack loaded into this tree would otherwise fail on the first `audio_attn1` it met.
public enum LTX2TransformerWeights {
    static let prefix = "transformer."
    private static let checkpointForm = ".emb.timestep_embedder."
    private static let moduleForm = ".emb."

    /// The name fragments that mark a tensor as the audio lane's, or the cross-modal attention
    /// that only runs with one. Shared with the quantization plan's omission list.
    public static let audioMarkers = ["audio", "a2v", "v2a", "av_ca"]

    /// Whether `key` belongs to the audio lane.
    public static func isAudio(_ key: String) -> Bool {
        audioMarkers.contains { key.contains($0) }
    }

    /// The pack's video-lane tensors under the names this module tree uses.
    public static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { renamed, entry in
            guard !isAudio(entry.key) else { return }
            renamed[moduleName(of: entry.key)] = entry.value
        }
    }

    /// One pack path under the name this module tree uses.
    public static func moduleName(of key: String) -> String {
        let bare = key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key
        return ("." + bare).replacingOccurrences(of: checkpointForm, with: moduleForm).dropFirst().description
    }

    /// A module path back under the name the pack and its manifest know it by.
    public static func checkpointName(of path: String) -> String {
        prefix + ("." + path).replacingOccurrences(of: moduleForm, with: checkpointForm).dropFirst()
    }
}

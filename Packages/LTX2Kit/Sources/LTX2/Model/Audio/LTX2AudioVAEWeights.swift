import Foundation
import MLX

/// The pack's names for the audio autoencoder's tensors against the decoder tree's paths.
///
/// Every tensor carries the file's `audio_vae.` prefix; the decoder's sit under `decoder.`
/// and the statistics under `per_channel_statistics.` with leading underscores the tree
/// leaves off (see `LTX2VAEWeights` for why). The encoder's tensors are dropped: nothing
/// here decodes what it encodes.
public enum LTX2AudioVAEWeights {
    /// The prefix every tensor of the pack's audio file carries.
    public static let prefix = "audio_vae."
    /// The prefix the decoder's tensors carry under it.
    public static let decoderPrefix = "audio_vae.decoder."
    /// The prefix the encoder's tensors carry, which the build leaves out.
    public static let encoderPrefix = "audio_vae.encoder."

    /// The statistics' paths, as (the file's name, the tree's).
    static let statisticsRenames = [
        ("per_channel_statistics._mean_of_means", "per_channel_statistics.mean"),
        ("per_channel_statistics._std_of_means", "per_channel_statistics.std"),
    ]

    /// The decoder's and statistics' weights, renamed for the tree; the encoder's dropped.
    public static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { renamed, entry in
            if entry.key.hasPrefix(decoderPrefix) {
                renamed[String(entry.key.dropFirst(decoderPrefix.count))] = entry.value
            } else if entry.key.hasPrefix(prefix) {
                let bare = String(entry.key.dropFirst(prefix.count))
                if let rename = statisticsRenames.first(where: { $0.0 == bare }) {
                    renamed[rename.1] = entry.value
                }
            }
        }
    }

    /// What the pack calls the parameter at `path` in the tree.
    public static func checkpointName(of path: String) -> String {
        if let rename = statisticsRenames.first(where: { $0.1 == path }) { return prefix + rename.0 }
        return decoderPrefix + path
    }
}

import Foundation
import MLX

/// The pack's names for the vocoder's tensors against the tree's paths.
///
/// The file prefixes everything with `vocoder.`; the first generator's tensors sit directly
/// under it (`conv_pre`, `ups`, `resblocks`, `act_post`, `conv_post`), the extender's under
/// `bwe_generator.` and the spectrogram's under `mel_stft.`. The tree nests the first
/// generator under `vocoder` too, so its paths are the file's with the prefix kept, and the
/// other two are the file's with the prefix dropped. The spectrogram's `inverse_basis` is
/// never read and is left out.
public enum LTX2VocoderWeights {
    /// The prefix every tensor of the pack's vocoder file carries.
    public static let prefix = "vocoder."
    /// The one tensor the tree has no use for.
    public static let unused = "vocoder.mel_stft.stft_fn.inverse_basis"

    /// The vocoder's weights, renamed for the tree.
    public static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.reduce(into: [:]) { renamed, entry in
            guard entry.key.hasPrefix(prefix), entry.key != unused else { return }
            let bare = String(entry.key.dropFirst(prefix.count))
            if bare.hasPrefix("bwe_generator.") || bare.hasPrefix("mel_stft.") {
                renamed[bare] = entry.value
            } else {
                renamed[prefix + bare] = entry.value
            }
        }
    }

    /// What the pack calls the parameter at `path` in the tree.
    public static func checkpointName(of path: String) -> String {
        path.hasPrefix(prefix) ? path : prefix + path
    }
}

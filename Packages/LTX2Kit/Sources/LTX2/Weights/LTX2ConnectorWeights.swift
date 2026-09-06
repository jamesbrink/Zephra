import Foundation
import MLX

/// The checkpoint's names for the text connector and the feature extractor, and the module
/// trees' names for them.
///
/// Two things differ. The checkpoint prefixes the connector `connector.video_embeddings_connector.`
/// and the projection `connector.text_embedding_projection.`, which the trees leave off. And it
/// numbers three layers by their position in a `Sequential` -- `net.0.proj`, `net.2`, `to_out.0`
/// -- which the trees name instead (`proj_in`, `proj_out`, `to_out`, the DiT's own names), because MLX rebuilds a numeric path as an array when it
/// unflattens weights and as a dictionary when it replaces modules, so a numbered child can be
/// loaded or packed but not both (the finding `QwenImageTransformerWeights` records).
enum LTX2ConnectorWeights {
    /// The checkpoint's prefix for the video connector's tensors.
    static let connectorPrefix = "connector.video_embeddings_connector."
    /// The checkpoint's prefix for the feature extractor's projection.
    static let projectionPrefix = "connector.text_embedding_projection."

    /// Longest first, so `net.0.proj` is matched before `net.0` could be.
    private static let renames = [
        (".net.0.proj.", ".proj_in."),
        (".net.2.", ".proj_out."),
        (".to_out.0.", ".to_out."),
    ]

    /// The connector's tensors under the names `LTX2TextConnector`'s tree uses; the audio
    /// connector's and everything else in the file are left out.
    static func connectorWeights(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        select(weights, under: connectorPrefix)
    }

    /// The video projection's tensors under the names `LTX2FeatureExtractor`'s tree uses.
    static func projectionWeights(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        select(weights, under: projectionPrefix).filter { $0.key.hasPrefix("video_aggregate_embed") }
    }

    /// A connector module path back under the checkpoint's name, for the manifest and the stream.
    static func checkpointName(of path: String) -> String {
        var bounded = "." + path + "."
        for (from, to) in renames where bounded.contains(to) {
            bounded = bounded.replacingOccurrences(of: to, with: from)
            break
        }
        return connectorPrefix + String(bounded.dropFirst().dropLast())
    }

    private static func select(_ weights: [String: MLXArray], under prefix: String)
        -> [String: MLXArray]
    {
        weights.reduce(into: [:]) { renamed, entry in
            guard entry.key.hasPrefix(prefix) else { return }
            var bounded = "." + entry.key.dropFirst(prefix.count) + "."
            for (from, to) in renames where bounded.contains(from) {
                bounded = bounded.replacingOccurrences(of: from, with: to)
                break
            }
            renamed[String(bounded.dropFirst().dropLast())] = entry.value
        }
    }
}

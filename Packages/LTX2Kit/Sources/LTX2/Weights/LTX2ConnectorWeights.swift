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
    /// The checkpoint's prefix for the audio connector's tensors.
    static let audioConnectorPrefix = "connector.audio_embeddings_connector."
    /// The checkpoint's prefix for both feature extractors' projections.
    static let projectionPrefix = "connector.text_embedding_projection."

    /// The connector prefix for `modality`'s lane.
    static func connectorPrefix(for modality: LTX2FeatureExtractor.Modality) -> String {
        modality == .video ? connectorPrefix : audioConnectorPrefix
    }

    /// Longest first, so `net.0.proj` is matched before `net.0` could be.
    private static let renames = [
        (".net.0.proj.", ".proj_in."),
        (".net.2.", ".proj_out."),
        (".to_out.0.", ".to_out."),
    ]

    /// One lane's connector tensors under the names `LTX2TextConnector`'s tree uses; the
    /// other lane's and everything else in the file are left out.
    static func connectorWeights(
        _ weights: [String: MLXArray], modality: LTX2FeatureExtractor.Modality = .video
    ) -> [String: MLXArray] {
        select(weights, under: connectorPrefix(for: modality))
    }

    /// One lane's projection under the name `LTX2FeatureExtractor`'s tree uses, which is the
    /// pack's with the lane's name taken off the front.
    static func projectionWeights(
        _ weights: [String: MLXArray], modality: LTX2FeatureExtractor.Modality = .video
    ) -> [String: MLXArray] {
        let name = modality.projectionName
        return select(weights, under: projectionPrefix).reduce(into: [:]) { renamed, entry in
            guard entry.key.hasPrefix(name + ".") else { return }
            renamed["aggregate_embed." + entry.key.dropFirst(name.count + 1)] = entry.value
        }
    }

    /// A projection module path back under the checkpoint's name for `modality`'s lane: the
    /// bare `aggregate_embed` the loader asks the manifest about, or a leaf under it.
    static func projectionCheckpointName(of path: String, modality: LTX2FeatureExtractor.Modality) -> String {
        guard path == "aggregate_embed" || path.hasPrefix("aggregate_embed.") else {
            return projectionPrefix + path
        }
        return projectionPrefix + modality.projectionName + path.dropFirst("aggregate_embed".count)
    }

    /// A connector module path back under the checkpoint's name, for the manifest and the stream.
    static func checkpointName(of path: String, modality: LTX2FeatureExtractor.Modality = .video) -> String {
        var bounded = "." + path + "."
        for (from, to) in renames where bounded.contains(to) {
            bounded = bounded.replacingOccurrences(of: to, with: from)
            break
        }
        return connectorPrefix(for: modality) + String(bounded.dropFirst().dropLast())
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

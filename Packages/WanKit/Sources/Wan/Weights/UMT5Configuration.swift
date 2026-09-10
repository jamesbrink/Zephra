import Foundation

/// `text_encoder/config.json`: the UMT5-XXL encoder Wan 2.2 conditions on.
///
/// The activation is not a free choice here. `feed_forward_proj` is `gated-gelu`, which the
/// reference reads as the gated feed-forward with `gelu_new`, the tanh approximation, and the
/// port implements that one shape only; a config asking for anything else is refused at read
/// time rather than run through the wrong arithmetic. Dropout is ignored, as inference does.
public struct UMT5Configuration: Codable, Hashable, Sendable {
    /// Width of the residual stream, and of every embedding the transformer reads.
    public let dModel: Int
    /// Width of one attention head.
    public let dKV: Int
    /// Attention heads, which is also the width of every relative attention bias table.
    public let numHeads: Int
    /// Width of the feed-forward network's hidden layer.
    public let dFF: Int
    /// Encoder blocks; all of them run.
    public let numLayers: Int
    /// Buckets a relative position falls into, half of them for each direction.
    public let relativeAttentionNumBuckets: Int
    /// Distances at or beyond this share the last bucket.
    public let relativeAttentionMaxDistance: Int
    /// Epsilon for every RMS norm in the stack.
    public let layerNormEpsilon: Float
    /// Tokens the embedding covers; more than the tokenizer names, as the release ships it.
    public let vocabSize: Int
    /// The id that pads a prompt, on the right.
    public let padTokenId: Int
    /// The id every prompt ends with.
    public let eosTokenId: Int
    /// `gated-gelu` is the one value the port runs.
    public let feedForwardProj: String

    /// What a config may ask for that this port does not do.
    public enum Unsupported: Error, Equatable, Sendable {
        /// The feed-forward is not the gated GELU the port implements.
        case feedForwardProj(String)
    }

    public init(
        dModel: Int, dKV: Int, numHeads: Int, dFF: Int, numLayers: Int,
        relativeAttentionNumBuckets: Int, relativeAttentionMaxDistance: Int,
        layerNormEpsilon: Float, vocabSize: Int, padTokenId: Int = 0, eosTokenId: Int = 1,
        feedForwardProj: String = "gated-gelu"
    ) {
        self.dModel = dModel
        self.dKV = dKV
        self.numHeads = numHeads
        self.dFF = dFF
        self.numLayers = numLayers
        self.relativeAttentionNumBuckets = relativeAttentionNumBuckets
        self.relativeAttentionMaxDistance = relativeAttentionMaxDistance
        self.layerNormEpsilon = layerNormEpsilon
        self.vocabSize = vocabSize
        self.padTokenId = padTokenId
        self.eosTokenId = eosTokenId
        self.feedForwardProj = feedForwardProj
    }

    /// Reads the release's `config.json`, refusing a feed-forward the port cannot run.
    public init(readingFrom url: URL) throws {
        let data = try Data(contentsOf: url)
        self = try JSONDecoder().decode(Self.self, from: data)
        guard feedForwardProj == "gated-gelu" else {
            throw Unsupported.feedForwardProj(feedForwardProj)
        }
    }

    enum CodingKeys: String, CodingKey {
        case dModel = "d_model", dKV = "d_kv", numHeads = "num_heads", dFF = "d_ff"
        case numLayers = "num_layers"
        case relativeAttentionNumBuckets = "relative_attention_num_buckets"
        case relativeAttentionMaxDistance = "relative_attention_max_distance"
        case layerNormEpsilon = "layer_norm_epsilon", vocabSize = "vocab_size"
        case padTokenId = "pad_token_id", eosTokenId = "eos_token_id"
        case feedForwardProj = "feed_forward_proj"
    }
}

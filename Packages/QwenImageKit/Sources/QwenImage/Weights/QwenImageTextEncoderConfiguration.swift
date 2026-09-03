import Foundation

/// `text_encoder/config.json`: the Qwen2.5-VL language stack Qwen-Image conditions on.
///
/// Only the language half is decoded. Text-to-image feeds the encoder token ids and a mask and
/// never supplies pixels, so the `vision_config` block and the vision tower's weights are read
/// by nothing here.
public struct QwenImageTextEncoderConfiguration: Hashable, Sendable, Decodable {
    /// Width of the model, and of the text stream the transformer receives.
    public let hiddenSize: Int
    /// Decoder layers.
    public let numHiddenLayers: Int
    /// Query heads.
    public let numAttentionHeads: Int
    /// Key and value heads. Fewer than the query heads: this is grouped-query attention.
    public let numKeyValueHeads: Int
    /// Width of the feed-forward network's hidden layer.
    public let intermediateSize: Int
    /// Epsilon for every RMS norm in the stack.
    public let rmsNormEps: Float
    /// Base of the rotary embedding's frequency ladder.
    public let ropeTheta: Float
    /// Tokens the embedding covers.
    public let vocabSize: Int

    /// Width of one attention head.
    public var headDim: Int { hiddenSize / numAttentionHeads }

    /// How many query heads share one key-value head.
    public var queryHeadsPerKeyValueHead: Int { numAttentionHeads / numKeyValueHeads }

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case intermediateSize = "intermediate_size"
        case rmsNormEps = "rms_norm_eps"
        case ropeTheta = "rope_theta"
        case vocabSize = "vocab_size"
    }

    /// Checks the divisions the shapes above assume.
    public func validated() throws -> Self {
        guard hiddenSize % numAttentionHeads == 0,
            numAttentionHeads % numKeyValueHeads == 0
        else {
            throw QwenImageConfigurationError.textEncoderHeadsDoNotDivide(
                hidden: hiddenSize, heads: numAttentionHeads, keyValueHeads: numKeyValueHeads)
        }
        return self
    }
}

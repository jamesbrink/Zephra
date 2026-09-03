import Foundation

/// `text_encoder/config.json`: the Qwen3 language stack FLUX.2 klein conditions on.
///
/// The transformer does not read the encoder's final output. It reads the running hidden state
/// after three of the layers and lays them side by side, which is why `hiddenStateTaps` is here
/// and why only the layers up to the deepest tap are ever built or loaded.
public struct Flux2TextEncoderConfiguration: Hashable, Sendable, Decodable {
    /// Width of the model, and of each tapped slice of the text stream.
    public let hiddenSize: Int
    /// Decoder layers in the published checkpoint. More than are needed; see `layersNeeded`.
    public let numHiddenLayers: Int
    /// Query heads.
    public let numAttentionHeads: Int
    /// Key and value heads. Fewer than the query heads: this is grouped-query attention.
    public let numKeyValueHeads: Int
    /// Width of one attention head. Stated, not derived: Qwen3-4B's heads are wider than its
    /// width divided by its head count.
    public let headDim: Int
    /// Width of the feed-forward network's hidden layer.
    public let intermediateSize: Int
    /// Epsilon for every RMS norm in the stack.
    public let rmsNormEps: Float
    /// Base of the rotary embedding's frequency ladder.
    public let ropeTheta: Float
    /// Tokens the embedding covers.
    public let vocabSize: Int

    /// Which layers' outputs the transformer conditions on, counting the way the reference does:
    /// tap `n` is the hidden state after `n` layers. The pipeline's, not the checkpoint's, which
    /// is why they are stated here rather than decoded.
    public let hiddenStateTaps = [9, 18, 27]

    /// Layers that must exist for the taps to be taken. The rest of the stack, and the final
    /// norm, are never built and never loaded.
    public var layersNeeded: Int { hiddenStateTaps.max() ?? 0 }

    /// How many query heads share one key-value head.
    public var queryHeadsPerKeyValueHead: Int { numAttentionHeads / numKeyValueHeads }

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case headDim = "head_dim"
        case intermediateSize = "intermediate_size"
        case rmsNormEps = "rms_norm_eps"
        case ropeTheta = "rope_theta"
        case vocabSize = "vocab_size"
    }

    /// Checks the divisions the shapes above assume, and that the taps are reachable.
    public func validated() throws -> Self {
        guard numAttentionHeads % numKeyValueHeads == 0 else {
            throw Flux2ConfigurationError.textEncoderHeadsDoNotDivide(
                heads: numAttentionHeads, keyValueHeads: numKeyValueHeads)
        }
        guard layersNeeded <= numHiddenLayers else {
            throw Flux2ConfigurationError.hiddenStateTapBeyondStack(
                tap: layersNeeded, layers: numHiddenLayers)
        }
        return self
    }
}

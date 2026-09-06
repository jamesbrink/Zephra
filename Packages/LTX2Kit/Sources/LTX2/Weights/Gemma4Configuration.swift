import Foundation

/// `gemma4-12b-ltx-v1/config.json`'s `text_config`: the Gemma 4 language stack LTX-2.5 reads.
///
/// Two kinds of layer live in one stack, and the checkpoint's shapes follow the kind: five
/// sliding-window layers (heads 256 wide, eight key-value heads, rope base 1e4) then one
/// full-attention layer (heads 512 wide, one key-value head, base 1e6 with only a quarter of the
/// head rotated, and no value projection at all, since `attention_k_eq_v` makes the keys serve
/// as values). `layer(at:)` answers which is which, so nothing else in the stack has to know.
public struct Gemma4Configuration: Hashable, Sendable {
    /// Width of the residual stream, and of every hidden state the connector reads.
    public let hiddenSize: Int
    /// Decoder layers; all of them run, since every hidden state is conditioning.
    public let numHiddenLayers: Int
    /// Query heads, the same count on every layer.
    public let numAttentionHeads: Int
    /// Key-value heads on a sliding layer.
    public let numKeyValueHeads: Int
    /// Width of one head on a sliding layer.
    public let headDim: Int
    /// Width of one head on a full-attention layer.
    public let globalHeadDim: Int
    /// Key-value heads on a full-attention layer.
    public let numGlobalKeyValueHeads: Int
    /// Whether full-attention layers reuse their keys as values and carry no `v_proj`.
    public let attentionKEqV: Bool
    /// `sliding_attention` or `full_attention`, one per layer.
    public let layerTypes: [String]
    /// Tokens a sliding layer's query can see, itself included.
    public let slidingWindow: Int
    /// Width of the feed-forward network's hidden layer.
    public let intermediateSize: Int
    /// Epsilon for every RMS norm in the stack.
    public let rmsNormEps: Float
    /// Tokens the embedding covers.
    public let vocabSize: Int
    /// The id that pads a prompt, on the left.
    public let padTokenId: Int
    /// The id every prompt begins with.
    public let bosTokenId: Int
    /// Rotary base for the sliding layers.
    public let slidingRopeTheta: Float
    /// Rotary base for the full-attention layers.
    public let fullRopeTheta: Float
    /// The share of a full-attention head that is rotated; the rest is position-blind.
    public let fullPartialRotaryFactor: Float

    /// The per-layer shape the attention module is built from.
    public struct LayerShape: Hashable, Sendable {
        public let isSliding: Bool
        public let headDim: Int
        public let keyValueHeads: Int
        public let hasValueProjection: Bool
        public let ropeTheta: Float
        public let rotaryFraction: Float
    }

    /// Which kind of layer `index` is, and the shapes that follow from it.
    public func layer(at index: Int) -> LayerShape {
        let sliding = layerTypes[index] == "sliding_attention"
        return LayerShape(
            isSliding: sliding,
            headDim: sliding ? headDim : globalHeadDim,
            keyValueHeads: sliding ? numKeyValueHeads : numGlobalKeyValueHeads,
            hasValueProjection: sliding || !attentionKEqV,
            ropeTheta: sliding ? slidingRopeTheta : fullRopeTheta,
            rotaryFraction: sliding ? 1 : fullPartialRotaryFactor)
    }

    /// Reads the pack's `config.json`, whose text stack sits under `text_config`.
    public init(readingFrom url: URL) throws {
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(File.self, from: data)
        self = try Self(file.textConfig)
    }

    init(_ text: TextConfig) throws {
        guard text.layerTypes.count == text.numHiddenLayers else {
            throw LTX2ConfigurationError.layerTypesDoNotMatchDepth(
                types: text.layerTypes.count, layers: text.numHiddenLayers)
        }
        hiddenSize = text.hiddenSize
        numHiddenLayers = text.numHiddenLayers
        numAttentionHeads = text.numAttentionHeads
        numKeyValueHeads = text.numKeyValueHeads
        headDim = text.headDim
        globalHeadDim = text.globalHeadDim ?? 512
        numGlobalKeyValueHeads = text.numGlobalKeyValueHeads ?? text.numKeyValueHeads
        attentionKEqV = text.attentionKEqV ?? true
        layerTypes = text.layerTypes
        slidingWindow = text.slidingWindow
        intermediateSize = text.intermediateSize
        rmsNormEps = text.rmsNormEps
        vocabSize = text.vocabSize
        padTokenId = text.padTokenId ?? 0
        bosTokenId = text.bosTokenId ?? 2
        slidingRopeTheta = text.ropeParameters.slidingAttention.ropeTheta
        fullRopeTheta = text.ropeParameters.fullAttention.ropeTheta
        fullPartialRotaryFactor = text.ropeParameters.fullAttention.partialRotaryFactor ?? 1
    }

    struct File: Decodable {
        let textConfig: TextConfig
        enum CodingKeys: String, CodingKey { case textConfig = "text_config" }
    }

    struct RopeParameters: Decodable {
        struct Entry: Decodable {
            let ropeTheta: Float
            let partialRotaryFactor: Float?
            enum CodingKeys: String, CodingKey {
                case ropeTheta = "rope_theta"
                case partialRotaryFactor = "partial_rotary_factor"
            }
        }
        let slidingAttention: Entry
        let fullAttention: Entry
        enum CodingKeys: String, CodingKey {
            case slidingAttention = "sliding_attention"
            case fullAttention = "full_attention"
        }
    }

    struct TextConfig: Decodable {
        let hiddenSize, numHiddenLayers, numAttentionHeads, numKeyValueHeads, headDim: Int
        let globalHeadDim, numGlobalKeyValueHeads: Int?
        let attentionKEqV: Bool?
        let layerTypes: [String]
        let slidingWindow, intermediateSize, vocabSize: Int
        let rmsNormEps: Float
        let padTokenId, bosTokenId: Int?
        let ropeParameters: RopeParameters
        enum CodingKeys: String, CodingKey {
            case hiddenSize = "hidden_size", numHiddenLayers = "num_hidden_layers"
            case numAttentionHeads = "num_attention_heads", numKeyValueHeads = "num_key_value_heads"
            case headDim = "head_dim", globalHeadDim = "global_head_dim"
            case numGlobalKeyValueHeads = "num_global_key_value_heads"
            case attentionKEqV = "attention_k_eq_v", layerTypes = "layer_types"
            case slidingWindow = "sliding_window", intermediateSize = "intermediate_size"
            case vocabSize = "vocab_size", rmsNormEps = "rms_norm_eps"
            case padTokenId = "pad_token_id", bosTokenId = "bos_token_id"
            case ropeParameters = "rope_parameters"
        }
    }
}

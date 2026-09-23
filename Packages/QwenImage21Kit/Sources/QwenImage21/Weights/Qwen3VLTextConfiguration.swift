import Foundation

/// `text_encoder/config.json`: the shape of the Qwen3-VL the prompt is read by.
///
/// The file nests two configurations. `text_config` is the 36-layer decoder whose penultimate
/// output the transformer conditions on; `vision_config` is the 27-block tower that turns a
/// reference picture into the image slots inside that prompt. They are decoded together because
/// the two only ever run together, and the ids that stitch them — the image pad, the vision
/// start and end — sit at the top level beside them.
public struct Qwen3VLTextConfiguration: Hashable, Sendable, Decodable {
    /// The decoder stack.
    public let text: Text
    /// The vision tower.
    public let vision: Vision
    /// The token the processor expands into one slot per merged vision patch.
    public let imageTokenID: Int
    /// The token that opens a picture's run of slots.
    public let visionStartTokenID: Int
    /// The token that closes it.
    public let visionEndTokenID: Int

    enum CodingKeys: String, CodingKey {
        case text = "text_config"
        case vision = "vision_config"
        case imageTokenID = "image_token_id"
        case visionStartTokenID = "vision_start_token_id"
        case visionEndTokenID = "vision_end_token_id"
    }

    /// `text_config`: the decoder the prompt's hidden states come from.
    public struct Text: Hashable, Sendable, Decodable {
        /// Width of the stream.
        public let hiddenSize: Int
        /// Width of the gated feed-forward's hidden layer.
        public let intermediateSize: Int
        /// Decoder layers. The transformer reads the output of the last one, *before* the
        /// stack's final norm.
        public let numHiddenLayers: Int
        /// Query heads.
        public let numAttentionHeads: Int
        /// Key and value heads: grouped-query attention, four queries to a group.
        public let numKeyValueHeads: Int
        /// Width of one head. Stated rather than derived, and not `hiddenSize / heads` in
        /// general.
        public let headDim: Int
        /// Epsilon for every RMS norm in the stack.
        public let rmsNormEps: Float
        /// Base of the rotary frequency ladder. Five million, not the usual ten thousand.
        public let ropeTheta: Double
        /// How the rotary is applied across the three position axes.
        public let ropeScaling: RopeScaling
        /// Rows in the embedding table, padded past the tokenizer's own vocabulary.
        public let vocabSize: Int
        /// The activation between the feed-forward's two halves.
        public let hiddenAct: String

        enum CodingKeys: String, CodingKey {
            case hiddenSize = "hidden_size"
            case intermediateSize = "intermediate_size"
            case numHiddenLayers = "num_hidden_layers"
            case numAttentionHeads = "num_attention_heads"
            case numKeyValueHeads = "num_key_value_heads"
            case headDim = "head_dim"
            case rmsNormEps = "rms_norm_eps"
            case ropeTheta = "rope_theta"
            case ropeScaling = "rope_scaling"
            case vocabSize = "vocab_size"
            case hiddenAct = "hidden_act"
        }
    }

    /// `text_config.rope_scaling`: multimodal rotary, interleaved rather than sectioned in
    /// blocks, which changes which channel carries which axis.
    public struct RopeScaling: Hashable, Sendable, Decodable {
        /// Channels given to the time, row and column axes, in that order.
        public let mropeSection: [Int]
        /// Whether the three axes are interleaved across the channels.
        public let mropeInterleaved: Bool
        /// The rotary family. `default` is the only one this port implements.
        public let ropeType: String

        enum CodingKeys: String, CodingKey {
            case mropeSection = "mrope_section"
            case mropeInterleaved = "mrope_interleaved"
            case ropeType = "rope_type"
        }
    }

    /// Refuses what the port implements only one branch of: the interleaved multimodal rotary,
    /// the grouped-query shapes that must divide, and a tower whose DeepStack taps are inside
    /// its own stack.
    public func validated() throws -> Self {
        guard text.ropeScaling.mropeInterleaved else {
            throw QwenImage21ConfigurationError.unsupportedValue(
                field: "rope_scaling.mrope_interleaved", value: "false")
        }
        guard text.ropeScaling.ropeType == "default" else {
            throw QwenImage21ConfigurationError.unsupportedValue(
                field: "rope_scaling.rope_type", value: text.ropeScaling.ropeType)
        }
        guard text.numKeyValueHeads > 0,
            text.numAttentionHeads.isMultiple(of: text.numKeyValueHeads)
        else {
            throw QwenImage21ConfigurationError.headsDoNotDivide(
                heads: text.numAttentionHeads, keyValueHeads: text.numKeyValueHeads)
        }
        guard vision.deepstackVisualIndexes.allSatisfy({ $0 < vision.depth }) else {
            throw QwenImage21ConfigurationError.unsupportedValue(
                field: "vision_config.deepstack_visual_indexes",
                value: String(describing: vision.deepstackVisualIndexes))
        }
        return self
    }
}

import Foundation

/// `transformer/config.json`: the shape of the FLUX.2 rectified-flow transformer.
///
/// Decoded rather than hard-coded because the same architecture ships at more than one size, and
/// a mismatch between these numbers and the weights is the kind of failure that loads
/// successfully and then produces noise.
public struct Flux2TransformerConfiguration: Hashable, Sendable, Decodable {
    /// Width of one attention head.
    public let attentionHeadDim: Int
    /// How the head's width is split across the four position axes: image index, row, column,
    /// and text position. Must sum to the head width.
    public let axesDimsRope: [Int]
    /// Epsilon for every norm in the stack, the per-head query and key norms included.
    public let eps: Float
    /// Whether the model takes a distilled guidance scale as an input. klein does not.
    public let guidanceEmbeds: Bool
    /// Channels arriving per token: the latent's 32 channels times the 2x2 patch.
    public let inChannels: Int
    /// Width of the text stream arriving from the encoder: three tapped layers side by side.
    public let jointAttentionDim: Int
    /// Feed-forward width as a multiple of the model's width.
    public let mlpRatio: Double
    /// Attention heads per block.
    public let numAttentionHeads: Int
    /// Dual-stream blocks, where text and image keep separate weights.
    public let numLayers: Int
    /// Single-stream blocks, where one set of weights sees text and image together.
    public let numSingleLayers: Int
    /// Channels leaving per token, or nil to match `inChannels`.
    private let outChannelsOrNil: Int?
    /// Base of the rotary frequency ladder.
    public let ropeTheta: Double
    /// Width of the sinusoidal timestep embedding before its projection.
    public let timestepGuidanceChannels: Int

    /// Channels leaving per token.
    public var outChannels: Int { outChannelsOrNil ?? inChannels }

    /// Width of the model: every head side by side.
    public var innerDim: Int { numAttentionHeads * attentionHeadDim }

    /// Width of the feed-forward hidden layer.
    public var mlpDim: Int { Int(Double(innerDim) * mlpRatio) }

    /// Width of the single block's fused projection: queries, keys, values, and both halves
    /// of the gated feed-forward, all from one matrix.
    public var fusedProjectionDim: Int { innerDim * 3 + mlpDim * 2 }

    enum CodingKeys: String, CodingKey {
        case attentionHeadDim = "attention_head_dim"
        case axesDimsRope = "axes_dims_rope"
        case eps
        case guidanceEmbeds = "guidance_embeds"
        case inChannels = "in_channels"
        case jointAttentionDim = "joint_attention_dim"
        case mlpRatio = "mlp_ratio"
        case numAttentionHeads = "num_attention_heads"
        case numLayers = "num_layers"
        case numSingleLayers = "num_single_layers"
        case outChannelsOrNil = "out_channels"
        case ropeTheta = "rope_theta"
        case timestepGuidanceChannels = "timestep_guidance_channels"
    }

    /// Checks the invariant that is silent when broken: rotary embeddings split a head's width
    /// across the axes, and half of each axis carries the cosine.
    public func validated() throws -> Self {
        guard axesDimsRope.reduce(0, +) == attentionHeadDim else {
            throw Flux2ConfigurationError.ropeAxesDoNotSumToHeadDim(
                axes: axesDimsRope, headDim: attentionHeadDim)
        }
        guard axesDimsRope.allSatisfy({ $0.isMultiple(of: 2) }) else {
            throw Flux2ConfigurationError.ropeAxisIsOdd(axes: axesDimsRope)
        }
        return self
    }
}

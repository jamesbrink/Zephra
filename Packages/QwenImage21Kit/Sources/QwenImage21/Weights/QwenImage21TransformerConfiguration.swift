import Foundation

/// `transformer/config.json`: the shape of the Qwen-Image 2.1 rectified-flow transformer.
///
/// Decoded rather than hard-coded because a mismatch between these numbers and the weights is
/// the kind of failure that loads successfully and then produces noise.
///
/// Two fields carry the biggest structural differences from 2512, and both are read here so a
/// later release cannot move them under the port: `patch_size` is 1, so one transformer token is
/// one latent cell and nothing is patchified anywhere; and `causal_condition` is true, which is
/// what says the reference images ahead of the target are attended to causally and get the
/// `t = 0` row of the shared modulation table.
public struct QwenImage21TransformerConfiguration: Hashable, Sendable, Decodable {
    /// Width of one attention head.
    public let attentionHeadDim: Int
    /// How the head's width is split across the three position axes: frame, row, column. Must
    /// sum to the head width.
    public let axesDimsRope: [Int]
    /// Width of the text stream arriving from the encoder. Equal to `innerDim`, which is why
    /// the text projection is square.
    public let contextInDim: Int
    /// Epsilon for every norm in the stack, the per-head query and key norms included.
    public let eps: Float
    /// Channels arriving per token. 2.1 does not patchify, so this is the latent's own 64.
    public let inChannels: Int
    /// Feed-forward width as a multiple of the model's width.
    public let mlpRatio: Double
    /// Attention heads per block.
    public let numAttentionHeads: Int
    /// Blocks in the stack. Every one of them reads the single shared modulation table.
    public let numLayers: Int
    /// Channels leaving per token, or nil to match `inChannels`.
    private let outChannelsOrNil: Int?
    /// Latent cells a token covers along each edge. 2.1 ships 1.
    public let patchSize: Int
    /// Whether the condition images ahead of the target are read causally, on the `t = 0`
    /// modulation row. 2.1 ships true.
    public let causalCondition: Bool

    /// Channels leaving per token.
    public var outChannels: Int { outChannelsOrNil ?? inChannels }

    /// Width of the model: every head side by side.
    public var innerDim: Int { numAttentionHeads * attentionHeadDim }

    /// Width of the gated feed-forward's hidden layer.
    public var mlpHiddenSize: Int { Int(Double(innerDim) * mlpRatio) }

    enum CodingKeys: String, CodingKey {
        case attentionHeadDim = "attention_head_dim"
        case axesDimsRope = "axes_dims_rope"
        case contextInDim = "context_in_dim"
        case eps
        case inChannels = "in_channels"
        case mlpRatio = "mlp_ratio"
        case numAttentionHeads = "num_attention_heads"
        case numLayers = "num_layers"
        case outChannelsOrNil = "out_channels"
        case patchSize = "patch_size"
        case causalCondition = "causal_condition"
    }

    /// Checks the invariants that are silent when broken: the rotary axes split a head's width
    /// across the three axes and each half carries the cosine, the text stream is the model's
    /// own width, and the patch is one cell — a 2 here would mean the port owes a patchify it
    /// does not have.
    public func validated() throws -> Self {
        guard patchSize == 1 else {
            throw QwenImage21ConfigurationError.unsupportedValue(
                field: "patch_size", value: String(patchSize))
        }
        guard contextInDim == innerDim else {
            throw QwenImage21ConfigurationError.contextWidthIsNotTheEncoder(
                context: contextInDim, hidden: innerDim)
        }
        guard axesDimsRope.reduce(0, +) == attentionHeadDim else {
            throw QwenImage21ConfigurationError.ropeAxesDoNotSumToHeadDim(
                axes: axesDimsRope, headDim: attentionHeadDim)
        }
        guard axesDimsRope.allSatisfy({ $0.isMultiple(of: 2) }) else {
            throw QwenImage21ConfigurationError.ropeAxisIsOdd(axes: axesDimsRope)
        }
        return self
    }
}

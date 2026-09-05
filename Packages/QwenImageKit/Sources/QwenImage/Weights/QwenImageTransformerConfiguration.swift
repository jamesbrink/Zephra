import Foundation

/// `transformer/config.json`: the shape of the MMDiT backbone.
///
/// Decoded rather than hard-coded because the same architecture ships at more than one size, and
/// a mismatch between these numbers and the weights is the kind of failure that loads
/// successfully and then produces noise.
public struct QwenImageTransformerConfiguration: Hashable, Sendable, Decodable {
    /// Width of one attention head.
    public let attentionHeadDim: Int
    /// How the head's width is split across the three position axes. Must sum to the head width.
    public let axesDimsRope: [Int]
    /// Whether the model takes a distilled guidance scale as an input. Qwen-Image-2512 does not.
    public let guidanceEmbeds: Bool
    /// Channels arriving per patch: the latent's 16 channels times the 2x2 patch.
    public let inChannels: Int
    /// Width of the text stream arriving from the encoder.
    public let jointAttentionDim: Int
    /// Attention heads per block.
    public let numAttentionHeads: Int
    /// Dual-stream blocks.
    public let numLayers: Int
    /// Channels leaving per patch, before unpacking: the latent's 16.
    public let outChannels: Int
    /// Latent cells per patch edge.
    public let patchSize: Int

    /// Width of the model: every head side by side.
    public var innerDim: Int { numAttentionHeads * attentionHeadDim }

    /// Width of one modulation projection: six chunks of the model's width, which is why these
    /// layers are a third of the parameters.
    public var modulationDim: Int { innerDim * 6 }

    enum CodingKeys: String, CodingKey {
        case attentionHeadDim = "attention_head_dim"
        case axesDimsRope = "axes_dims_rope"
        case guidanceEmbeds = "guidance_embeds"
        case inChannels = "in_channels"
        case jointAttentionDim = "joint_attention_dim"
        case numAttentionHeads = "num_attention_heads"
        case numLayers = "num_layers"
        case outChannels = "out_channels"
        case patchSize = "patch_size"
    }

    /// Checks the invariants that are silent when broken: rotary embeddings split a head's
    /// width across three axes, and half of each axis carries the cosine; the packing is the
    /// two-by-two `QwenImageLatentPacking` implements; and the port has no guidance embedder,
    /// so a config asking for one is refused rather than ignored.
    public func validated() throws -> Self {
        guard !guidanceEmbeds else {
            throw QwenImageConfigurationError.unsupportedValue(field: "guidance_embeds", value: "true")
        }
        guard patchSize == QwenImageLatentPacking.patchSize else {
            throw QwenImageConfigurationError.unsupportedValue(
                field: "patch_size", value: String(patchSize))
        }
        guard axesDimsRope.reduce(0, +) == attentionHeadDim else {
            throw QwenImageConfigurationError.ropeAxesDoNotSumToHeadDim(
                axes: axesDimsRope, headDim: attentionHeadDim)
        }
        guard axesDimsRope.allSatisfy({ $0.isMultiple(of: 2) }) else {
            throw QwenImageConfigurationError.ropeAxisIsOdd(axes: axesDimsRope)
        }
        return self
    }
}

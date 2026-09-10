import Foundation

/// The shape of the Wan 2.2 transformer, read from `transformer/config.json`, with TI2V-5B's
/// values as the defaults.
///
/// The keys are diffusers' `WanTransformer3DModel` arguments, spelled as the file spells them.
/// Two of them describe modules this port does not build: `image_dim` and
/// `added_kv_proj_dim` are the CLIP image path of the Wan 2.1 image-to-video models and are
/// null for TI2V-5B, which conditions on a picture through the latent instead; a
/// configuration naming either is refused at read, before a weight is looked for.
public struct WanTransformerConfiguration: Codable, Hashable, Sendable {
    /// Latent cells one token covers, as frames, rows, columns.
    public var patchSize: [Int]
    /// Attention heads.
    public var numAttentionHeads: Int
    /// Width of one head; `heads * headDim` is the stream's width.
    public var attentionHeadDim: Int
    /// Latent channels in.
    public var inChannels: Int
    /// Latent channels the head projects back to.
    public var outChannels: Int
    /// Width of the text embeddings the condition embedder reads.
    public var textDim: Int
    /// Channels of the timestep's sinusoid.
    public var freqDim: Int
    /// The feed-forward's hidden width.
    public var ffnDim: Int
    /// How many blocks.
    public var numLayers: Int
    /// Whether `norm2`, before the cross-attention, carries a weight and bias.
    public var crossAttnNorm: Bool
    /// How queries and keys are normalised; only `rms_norm_across_heads` is built.
    public var qkNorm: String?
    /// Epsilon of every norm.
    public var eps: Float
    /// Positions per axis the rotary tables are built over.
    public var ropeMaxSeqLen: Int
    /// The CLIP image path's width; null for TI2V-5B.
    public var imageDim: Int?
    /// The CLIP image path's key-value width; null for TI2V-5B.
    public var addedKvProjDim: Int?

    enum CodingKeys: String, CodingKey {
        case patchSize = "patch_size", numAttentionHeads = "num_attention_heads"
        case attentionHeadDim = "attention_head_dim", inChannels = "in_channels"
        case outChannels = "out_channels", textDim = "text_dim", freqDim = "freq_dim"
        case ffnDim = "ffn_dim", numLayers = "num_layers", crossAttnNorm = "cross_attn_norm"
        case qkNorm = "qk_norm", eps, ropeMaxSeqLen = "rope_max_seq_len"
        case imageDim = "image_dim", addedKvProjDim = "added_kv_proj_dim"
    }

    /// Creates a configuration; the defaults are TI2V-5B's.
    public init(
        patchSize: [Int] = [1, 2, 2],
        numAttentionHeads: Int = 24,
        attentionHeadDim: Int = 128,
        inChannels: Int = 48,
        outChannels: Int = 48,
        textDim: Int = 4096,
        freqDim: Int = 256,
        ffnDim: Int = 14336,
        numLayers: Int = 30,
        crossAttnNorm: Bool = true,
        qkNorm: String? = "rms_norm_across_heads",
        eps: Float = 1e-6,
        ropeMaxSeqLen: Int = 1024
    ) {
        self.patchSize = patchSize
        self.numAttentionHeads = numAttentionHeads
        self.attentionHeadDim = attentionHeadDim
        self.inChannels = inChannels
        self.outChannels = outChannels
        self.textDim = textDim
        self.freqDim = freqDim
        self.ffnDim = ffnDim
        self.numLayers = numLayers
        self.crossAttnNorm = crossAttnNorm
        self.qkNorm = qkNorm
        self.eps = eps
        self.ropeMaxSeqLen = ropeMaxSeqLen
    }

    /// Reads a release's `transformer/config.json`.
    public init(readingFrom url: URL) throws {
        let decoded = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard decoded.imageDim == nil, decoded.addedKvProjDim == nil else {
            throw WanTransformerConfigurationError.imageConditioningNotSupported
        }
        guard decoded.qkNorm == "rms_norm_across_heads" else {
            throw WanTransformerConfigurationError.unsupportedQKNorm(decoded.qkNorm)
        }
        self = decoded
    }

    /// The stream's width.
    public var innerDim: Int { numAttentionHeads * attentionHeadDim }
    /// Latent values one token projects to: the output channels times the patch's cells.
    public var patchValues: Int { outChannels * patchSize.reduce(1, *) }
    /// Rows a block's `scale_shift_table` holds: shift, scale and gate for the self-attention
    /// and for the feed-forward.
    public static let blockModulationRows = 6
    /// Rows the head's `scale_shift_table` holds: shift and scale.
    public static let headModulationRows = 2
}

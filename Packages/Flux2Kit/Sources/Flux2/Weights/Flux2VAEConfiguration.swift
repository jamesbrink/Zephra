import Foundation

/// `vae/config.json`: the shape of the 2-D KL autoencoder.
///
/// There is no scaling or shift factor. FLUX.2 normalises its latent with batch-norm running
/// statistics instead, held in the weights as `bn.running_mean` and `bn.running_var` over the
/// packed 128-channel latent; `batchNormEps` is the only number about them that lives here.
public struct Flux2VAEConfiguration: Hashable, Sendable, Decodable {
    /// Feature width at each stage, finest first.
    public let blockOutChannels: [Int]
    /// Residual blocks per encoder stage. The decoder has one more per stage.
    public let layersPerBlock: Int
    /// Latent channels before packing.
    public let latentChannels: Int
    /// Groups in every group norm.
    public let normNumGroups: Int
    /// Whether the middle block carries an attention layer. It does.
    public let midBlockAddAttention: Bool
    /// Latent cells along each edge of a packed patch.
    public let patchSize: [Int]
    /// Epsilon added to the running variance before the square root.
    public let batchNormEps: Float

    /// How much smaller the latent is than the image, on each spatial axis.
    public var spatialScale: Int { 1 << (blockOutChannels.count - 1) }

    /// Channels of the packed latent: each patch's cells stacked into the channel axis.
    public var packedChannels: Int { latentChannels * patchSize.reduce(1, *) }

    enum CodingKeys: String, CodingKey {
        case blockOutChannels = "block_out_channels"
        case layersPerBlock = "layers_per_block"
        case latentChannels = "latent_channels"
        case normNumGroups = "norm_num_groups"
        case midBlockAddAttention = "mid_block_add_attention"
        case patchSize = "patch_size"
        case batchNormEps = "batch_norm_eps"
    }

    /// Checks what the packing and the norms assume.
    public func validated() throws -> Self {
        guard patchSize == [2, 2] else {
            throw Flux2ConfigurationError.unexpectedPatchSize(patchSize)
        }
        guard blockOutChannels.allSatisfy({ $0.isMultiple(of: normNumGroups) }) else {
            throw Flux2ConfigurationError.groupsDoNotDivideChannels(
                groups: normNumGroups, channels: blockOutChannels)
        }
        return self
    }
}

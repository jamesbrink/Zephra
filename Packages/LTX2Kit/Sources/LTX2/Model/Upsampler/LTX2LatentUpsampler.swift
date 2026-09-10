import Foundation
import MLX
import MLXNN

/// LTX-2.5's spatial latent upsampler: a latent to one twice as tall and twice as wide, in the
/// same 128 channels, for the second stage of a two-stage run to refine.
///
/// `initial_conv` to the middle width, a GroupNorm and SiLU, a stage of residual blocks, a
/// per-frame pixel shuffle that doubles height and width, a second stage of blocks, and
/// `final_conv` back to the latent's channels. The network works in the autoencoder's own
/// space, as the reference's upsample pipeline denormalises a latent before it and the next
/// stage normalises what comes out; `upsample` does both around the network, so what it takes
/// and hands back are both in the transformer's space, like everything else the loop holds.
/// The frame count never changes: every convolution is zero-padded in time.
///
/// Activations are channels-last from the first convolution to the last; the latent arrives
/// channels-first because that is how every loop holds it, and is transposed once at each
/// door. The compute dtype is whatever the weights were loaded in: bfloat16 from the pack,
/// float32 from a fixture.
public final class LTX2LatentUpsampler: Module {
    @ModuleInfo(key: "initial_conv") var initialConv: Conv3d
    @ModuleInfo(key: "initial_norm") var initialNorm: GroupNorm
    @ModuleInfo(key: "res_blocks") var resBlocks: [LTX2UpsamplerResBlock]
    /// The reference's `Sequential` of one convolution and the shuffle, held as the list the
    /// checkpoint's `upsampler.0` spells; see `LTX2SpatialPixelShuffle`.
    @ModuleInfo(key: "upsampler") var upsampler: [Conv2d]
    @ModuleInfo(key: "post_upsample_res_blocks") var postBlocks: [LTX2UpsamplerResBlock]
    @ModuleInfo(key: "final_conv") var finalConv: Conv3d

    public let configuration: LTX2UpsamplerConfiguration
    /// The pack's config file for the published weights, beside them at the pack's root and at
    /// a packed variant's.
    public static let configFileName = "spatial_upscaler_x2_v1_1_config.json"

    public init(_ configuration: LTX2UpsamplerConfiguration = .x2) {
        self.configuration = configuration
        let (channels, width) = (configuration.inChannels, configuration.midChannels)
        _initialConv.wrappedValue = Conv3d(
            inputChannels: channels, outputChannels: width, kernelSize: 3, padding: 1)
        _initialNorm.wrappedValue = .ltx2Upsampler(channels: width)
        _resBlocks.wrappedValue = (0..<configuration.blocksPerStage).map { _ in
            LTX2UpsamplerResBlock(channels: width)
        }
        _upsampler.wrappedValue = [
            Conv2d(inputChannels: width, outputChannels: 4 * width, kernelSize: 3, padding: 1)
        ]
        _postBlocks.wrappedValue = (0..<configuration.blocksPerStage).map { _ in
            LTX2UpsamplerResBlock(channels: width)
        }
        _finalConv.wrappedValue = Conv3d(
            inputChannels: width, outputChannels: channels, kernelSize: 3, padding: 1)
    }

    /// The dtype the upsampler computes in: the one its weights hold.
    public var dtype: DType { initialConv.weight.dtype }

    /// Fills the tree from the pack's or a fixture's `spatial_upscaler_x2_v1_1.*` tensors.
    /// Every parameter must be covered exactly: a tree with a block's weights missing would
    /// still run and double the latent into noise of the right shape.
    public func load(weights: [String: MLXArray]) throws {
        try update(
            parameters: ModuleParameters.unflattened(LTX2UpsamplerWeights.sanitized(weights)),
            verify: .all)
    }

    /// Doubles a normalised latent, `[1, channels, frames, height, width]` as the loop holds
    /// it, to `[1, channels, frames, 2·height, 2·width]`, still normalised.
    ///
    /// `statistics` is the decoder's per-channel pair: the latent is denormalised by it in its
    /// own dtype before the network and normalised again after, in that dtype, so the network
    /// runs in the autoencoder's space and the rounding of a bfloat16 pack touches only the
    /// network's own arithmetic.
    public func upsample(_ latent: MLXArray, statistics: LTX2PerChannelStatistics) -> MLXArray {
        let raw = statistics.denormalised(latent.transposed(0, 2, 3, 4, 1))
        let doubled = callAsFunction(raw.asType(dtype)).asType(latent.dtype)
        return statistics.normalised(doubled).transposed(0, 4, 1, 2, 3)
    }

    /// The network alone, over a denormalised channels-last latent `[b, f, h, w, c]`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var x = silu(initialNorm(initialConv(x)))
        for block in resBlocks { x = block(x) }
        x = LTX2SpatialPixelShuffle.doubled(x, through: upsampler)
        for block in postBlocks { x = block(x) }
        return finalConv(x)
    }
}

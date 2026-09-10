import Foundation
import MLX
import MLXNN

/// The encoder half, `encoder.*` in the checkpoint: one chunk of patchified frames to twice
/// the latent's channels, a mean and a log-variance.
///
/// `conv_in`, then a residual stage per entry of `dim_mult` -- each but the last halving
/// space, the ones `temperal_downsample` names halving time too -- then the mid block, then
/// norm, SiLU and `conv_out`. Every convolution is causal and reads the cache, so this runs
/// one chunk at a time and `WanVideoAutoencoder.encode` is what walks a clip.
final class WanEncoder3d: Module {
    @ModuleInfo(key: "conv_in") var convIn: WanCausalConv3d
    @ModuleInfo(key: "down_blocks") var downBlocks: [WanResidualDownBlock]
    @ModuleInfo(key: "mid_block") var midBlock: WanMidBlock
    @ModuleInfo(key: "norm_out") var normOut: WanRMSNorm
    @ModuleInfo(key: "conv_out") var convOut: WanCausalConv3d

    init(_ configuration: WanVAEConfiguration) {
        let widths = configuration.encoderWidths
        let last = widths[widths.count - 1]
        _convIn.wrappedValue = WanCausalConv3d(
            inputChannels: configuration.inChannels, outputChannels: widths[0], kernelSize: 3, padding: 1)
        _downBlocks.wrappedValue = (0..<configuration.dimMult.count).map { index in
            let halvesSpace = index != configuration.dimMult.count - 1
            return WanResidualDownBlock(
                inputChannels: widths[index], outputChannels: widths[index + 1],
                blocks: configuration.numResBlocks,
                halvesSpace: halvesSpace,
                halvesTime: halvesSpace && configuration.temporalDownsample[index])
        }
        _midBlock.wrappedValue = WanMidBlock(channels: last)
        _normOut.wrappedValue = WanRMSNorm(channels: last)
        _convOut.wrappedValue = WanCausalConv3d(
            inputChannels: last, outputChannels: 2 * configuration.zDim, kernelSize: 3, padding: 1)
        super.init()
    }

    /// One chunk, `[batch, frames, height, width, channels]` after the patchify, with the cache
    /// carried from the chunk before.
    func callAsFunction(_ x: MLXArray, cache: WanFeatureCache) -> MLXArray {
        var x = convIn(x, cache: cache)
        for block in downBlocks {
            x = block(x, cache: cache)
        }
        x = midBlock(x, cache: cache)
        return convOut(silu(normOut(x)), cache: cache)
    }
}

import Foundation
import MLX
import MLXNN

/// The decoder half, `decoder.*` in the checkpoint: one latent frame to the patchified pixels
/// it stands for.
///
/// The encoder's mirror, wider: `conv_in`, the mid block, a residual stage per entry of
/// `dim_mult` read backwards -- each but the last doubling space, the first ones doubling time
/// where the encoder's last ones halved it -- then norm, SiLU and `conv_out`. Runs one chunk
/// at a time on the cache like the encoder; `firstChunk` is what the shortcuts need to know
/// to drop the frames they would otherwise put before the first.
final class WanDecoder3d: Module {
    @ModuleInfo(key: "conv_in") var convIn: WanCausalConv3d
    @ModuleInfo(key: "mid_block") var midBlock: WanMidBlock
    @ModuleInfo(key: "up_blocks") var upBlocks: [WanResidualUpBlock]
    @ModuleInfo(key: "norm_out") var normOut: WanRMSNorm
    @ModuleInfo(key: "conv_out") var convOut: WanCausalConv3d

    init(_ configuration: WanVAEConfiguration) {
        let widths = configuration.decoderWidths
        let last = widths[widths.count - 1]
        let doublesTime = Array(configuration.temporalDownsample.reversed())
        _convIn.wrappedValue = WanCausalConv3d(
            inputChannels: configuration.zDim, outputChannels: widths[0], kernelSize: 3, padding: 1)
        _midBlock.wrappedValue = WanMidBlock(channels: widths[0])
        _upBlocks.wrappedValue = (0..<configuration.dimMult.count).map { index in
            let doublesSpace = index != configuration.dimMult.count - 1
            return WanResidualUpBlock(
                inputChannels: widths[index], outputChannels: widths[index + 1],
                blocks: configuration.numResBlocks,
                doublesSpace: doublesSpace,
                doublesTime: doublesSpace && doublesTime[index])
        }
        _normOut.wrappedValue = WanRMSNorm(channels: last)
        _convOut.wrappedValue = WanCausalConv3d(
            inputChannels: last, outputChannels: configuration.outChannels, kernelSize: 3, padding: 1)
        super.init()
    }

    /// One chunk of latent frames, `[batch, frames, height, width, channels]`, with the cache
    /// carried from the chunk before.
    func callAsFunction(_ x: MLXArray, cache: WanFeatureCache, firstChunk: Bool) -> MLXArray {
        var x = convIn(x, cache: cache)
        x = midBlock(x, cache: cache)
        for block in upBlocks {
            x = block(x, cache: cache, firstChunk: firstChunk)
        }
        return convOut(silu(normOut(x)), cache: cache)
    }
}

import Foundation
import MLX
import MLXNN

/// The encoder half, `encoder.*` in the checkpoint: an RGBA picture to twice the latent's
/// channels, a mean and a log-variance side by side.
///
/// `conv_in`, then a residual stage per entry of `dim_mult` -- each but the last halving space,
/// the ones `temperal_downsample` names folding the frame axis into their shortcut too -- then
/// the mid block, then norm, SiLU and `conv_out`. With `dim_mult` five long and four stages
/// halving, a picture comes out at a sixteenth of its size.
///
/// `conv_out` writes **128 channels** for a 64-channel latent, and stays 128 wide even though
/// inference never reads the second half: `DiagonalGaussianDistribution` splits it into a mean
/// and a log-variance, and the pipeline asks for the posterior's mode, which is the mean.
final class QwenImage21VAEEncoder: Module {
    @ModuleInfo(key: "conv_in") var convIn: QwenImage21CausalConv
    @ModuleInfo(key: "down_blocks") var downBlocks: [QwenImage21ResidualDownBlock]
    @ModuleInfo(key: "mid_block") var midBlock: QwenImage21VAEMidBlock
    @ModuleInfo(key: "norm_out") var normOut: QwenImage21VAENorm
    @ModuleInfo(key: "conv_out") var convOut: QwenImage21CausalConv

    init(_ configuration: QwenImage21VAEConfiguration) {
        let dims = configuration.encoderStageDims
        let stages = configuration.dimMult.count
        let last = dims[stages]
        _convIn.wrappedValue = QwenImage21CausalConv(
            inputChannels: configuration.inChannels, outputChannels: dims[0],
            kernelSize: 3, padding: 1)
        _downBlocks.wrappedValue = (0..<stages).map { index in
            let halvesSpace = index != stages - 1
            return QwenImage21ResidualDownBlock(
                inputChannels: dims[index], outputChannels: dims[index + 1],
                blocks: configuration.numResBlocks,
                halvesSpace: halvesSpace,
                foldsTime: halvesSpace && configuration.temperalDownsample[index])
        }
        _midBlock.wrappedValue = QwenImage21VAEMidBlock(channels: last)
        _normOut.wrappedValue = QwenImage21VAENorm(channels: last)
        _convOut.wrappedValue = QwenImage21CausalConv(
            inputChannels: last, outputChannels: 2 * configuration.zDim,
            kernelSize: 3, padding: 1)
        super.init()
    }

    /// `[batch, height, width, 4]` in the range -1 to 1, to
    /// `[batch, height / 16, width / 16, 2 * zDim]`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var x = convIn(x)
        for block in downBlocks {
            x = block(x)
        }
        x = midBlock(x)
        return convOut(silu(normOut(x)))
    }
}

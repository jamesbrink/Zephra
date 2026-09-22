import Foundation
import MLX
import MLXNN

/// The decoder half, `decoder.*` in the checkpoint: a 64-channel latent to the RGBA picture it
/// stands for, sixteen times its size on each edge.
///
/// The encoder's mirror, and half again as wide: `conv_in`, the mid block, a residual stage per
/// entry of `dim_mult` read backwards -- each but the last doubling space, the first ones
/// unfolding time where the encoder's last ones folded it -- then norm, SiLU and `conv_out` to
/// **four** channels. The widths come from `decoder_base_dim`, 144, not from `base_dim`.
///
/// Each stage holds `num_res_blocks + 1` residual blocks, three in the release, one more than
/// the encoder's stages.
final class QwenImage21VAEDecoder: Module {
    @ModuleInfo(key: "conv_in") var convIn: QwenImage21CausalConv
    @ModuleInfo(key: "mid_block") var midBlock: QwenImage21VAEMidBlock
    @ModuleInfo(key: "up_blocks") var upBlocks: [QwenImage21ResidualUpBlock]
    @ModuleInfo(key: "norm_out") var normOut: QwenImage21VAENorm
    @ModuleInfo(key: "conv_out") var convOut: QwenImage21CausalConv

    init(_ configuration: QwenImage21VAEConfiguration) {
        let dims = configuration.decoderStageDims
        let stages = configuration.dimMult.count
        let last = dims[stages]
        let unfoldsTime = configuration.temperalUpsample
        _convIn.wrappedValue = QwenImage21CausalConv(
            inputChannels: configuration.zDim, outputChannels: dims[0],
            kernelSize: 3, padding: 1)
        _midBlock.wrappedValue = QwenImage21VAEMidBlock(channels: dims[0])
        _upBlocks.wrappedValue = (0..<stages).map { index in
            let doublesSpace = index != stages - 1
            return QwenImage21ResidualUpBlock(
                inputChannels: dims[index], outputChannels: dims[index + 1],
                blocks: configuration.numResBlocks,
                doublesSpace: doublesSpace,
                unfoldsTime: doublesSpace && unfoldsTime[index])
        }
        _normOut.wrappedValue = QwenImage21VAENorm(channels: last)
        _convOut.wrappedValue = QwenImage21CausalConv(
            inputChannels: last, outputChannels: configuration.outChannels,
            kernelSize: 3, padding: 1)
        super.init()
    }

    /// `[batch, height, width, zDim]` to `[batch, height * 16, width * 16, 4]`, unclamped --
    /// the reference clamps in `_decode`, outside the decoder, and so does
    /// `QwenImage21Autoencoder`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var x = midBlock(convIn(x))
        for block in upBlocks {
            x = block(x)
        }
        return convOut(silu(normOut(x)))
    }
}

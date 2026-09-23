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
    ///
    /// **Evaluated a stage at a time**, and inside each stage around its upsampler (see
    /// `QwenImage21ResidualUpBlock`). A whole decode handed to MLX as one graph keeps every
    /// stage's scratch alive together -- the 3 x 3 convolutions at these widths run as
    /// Winograd, whose transformed inputs and outputs are held until their command buffer
    /// completes -- and at 1024 square that measured 15.1 GB over the weights. Evaluated in
    /// stages the same operations are 9.5 GB over them: nothing is computed differently, only
    /// sooner.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        tail(head(x))
    }

    /// `conv_in` and the mid block, at the latent's own size: the part of the decode that must
    /// see the **whole** picture, because the mid block's attention is one head over every
    /// cell of it. A tiled decode runs this once, whole, and tiles only `tail`; tiling it too
    /// had each tile attend to itself alone, which decoded each tile as a different picture --
    /// on a 16 GB Mac, the tile grid drawn into the alpha as ghosted rectangles.
    func head(_ x: MLXArray) -> MLXArray {
        let x = midBlock(convIn(x))
        eval(x)
        return x
    }

    /// The upsampling stages and the output: local convolutions only, so tiling them is the
    /// overlap approximation `TiledDecode` makes and nothing worse.
    func tail(_ x: MLXArray) -> MLXArray {
        var x = x
        for block in upBlocks {
            x = block(x)
            eval(x)
        }
        return convOut(silu(normOut(x)))
    }
}

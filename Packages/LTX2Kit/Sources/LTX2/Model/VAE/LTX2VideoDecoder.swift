import Foundation
import MLX
import MLXNN

/// LTX-2.5's convolutional video decoder: a 128-channel latent to frames of pixels.
///
/// `conv_in`, then the layout's residual stages with a depth-to-space upsampler between each
/// pair, then pixel-norm, SiLU, `conv_out` to `3 · patch²` channels and a spatial unpatchify.
/// Activations are channels-last, `[batch, frames, height, width, channels]`, from the first
/// convolution to the last; the latent arrives channels-first because that is how every loop
/// and every reference holds it, and is transposed once at the door.
///
/// The compute dtype is whatever the weights were loaded in. The reference decodes in
/// bfloat16, and so does this port, which is a departure from Zephra's other autoencoders
/// (float32) recorded in `PROVENANCE.md`: a 3-D decode at 768 x 512 x 49 is a gigabyte of
/// activations, and halving that is worth more here than the last bit of precision.
public final class LTX2VideoDecoder: Module {
    @ModuleInfo(key: "conv_in") var convIn: LTX2VideoConv3d
    @ModuleInfo(key: "up_blocks") var upBlocks: [Module]
    @ModuleInfo(key: "conv_out") var convOut: LTX2VideoConv3d
    @ModuleInfo(key: "per_channel_statistics") var statistics: LTX2PerChannelStatistics

    public let layout: LTX2VideoDecoderLayout

    public init(_ layout: LTX2VideoDecoderLayout = .ltx25) {
        self.layout = layout
        let first = layout.stages[0].channels
        _convIn.wrappedValue = LTX2VideoConv3d(
            inputChannels: layout.latentChannels, outputChannels: first)
        var blocks: [Module] = []
        for (index, stage) in layout.stages.enumerated() {
            if index > 0 {
                blocks.append(
                    LTX2DepthToSpaceUpsample(
                        inputChannels: layout.stages[index - 1].channels,
                        outputChannels: stage.channels,
                        stride: layout.strides[index - 1]))
            }
            blocks.append(LTX2ResnetStage(channels: stage.channels, blocks: stage.blocks))
        }
        _upBlocks.wrappedValue = blocks
        let last = layout.stages[layout.stages.count - 1].channels
        _convOut.wrappedValue = LTX2VideoConv3d(
            inputChannels: last, outputChannels: 3 * layout.patchSize * layout.patchSize)
        _statistics.wrappedValue = LTX2PerChannelStatistics(channels: layout.latentChannels)
    }

    /// The dtype the decoder computes in: the one its weights hold.
    public var dtype: DType { convIn.conv.weight.dtype }

    /// Fills the tree from the pack's or a fixture's `vae_decoder.*` tensors. Every parameter
    /// must be covered exactly: a decoder with a stage's weights missing would still run and
    /// decode to noise of the right shape.
    public func load(weights: [String: MLXArray]) throws {
        try update(
            parameters: ModuleParameters.unflattened(LTX2VAEWeights.sanitized(weights)),
            verify: .all)
    }

    /// Decodes a normalised latent, `[1, channels, frames, height, width]` as the loop holds it,
    /// to pixels `[1, frames', height', width', 3]` in the range -1 to 1, unclipped.
    public func decode(_ latent: MLXArray) -> MLXArray {
        var x = statistics.denormalised(latent.transposed(0, 2, 3, 4, 1).asType(dtype))
        x = convIn(x)
        for block in upBlocks {
            switch block {
            case let stage as LTX2ResnetStage: x = stage(x)
            case let upsample as LTX2DepthToSpaceUpsample: x = upsample(x)
            default: preconditionFailure("up_blocks holds only stages and upsamplers")
            }
        }
        x = convOut(silu(LTX2PixelNorm.apply(x)))
        return Self.unpatchified(x, patch: layout.patchSize)
    }

    /// `[b, f, h, w, 3·p·p]` to `[b, f, h·p, w·p, 3]`, in the reference's channel order: the
    /// `p·p` channels of one colour run over the width offset first, then the height offset.
    static func unpatchified(_ x: MLXArray, patch p: Int) -> MLXArray {
        let (batch, frames, height, width) = (x.dim(0), x.dim(1), x.dim(2), x.dim(3))
        return x.reshaped([batch, frames, height, width, 3, p, p])
            .transposed(0, 1, 2, 6, 3, 5, 4)
            .reshaped([batch, frames, height * p, width * p, 3])
    }
}

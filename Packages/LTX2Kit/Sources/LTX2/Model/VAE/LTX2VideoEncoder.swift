import Foundation
import MLX
import MLXNN

/// LTX-2.5's convolutional video encoder: frames of pixels to a 128-channel latent.
///
/// The mirror of `LTX2VideoDecoder`. A spatial patchify folds a 4 x 4 patch of three colours
/// into 48 channels, then `conv_in`, then the layout's residual stages with a space-to-depth
/// downsampler between each pair, then pixel-norm, SiLU and `conv_out`. Every convolution is
/// causal in time, which is what gives a single picture a latent frame of its own that means
/// the same thing at the head of a longer clip — the whole basis of holding a first frame.
///
/// `conv_out` writes one channel more than the latent: the reference's diagonal Gaussian carries
/// a mean and a log-variance, and both LTX-2 pipelines encode with `sample_mode: "argmax"`, so
/// the mean is taken and the extra channel is dropped rather than sampled from. The result is
/// normalised by the encoder's own per-channel statistics, which are a different pair from the
/// decoder's and under different names.
///
/// Activations are channels-last from the patchify to the last convolution; the latent leaves
/// channels-first because that is how every loop and every reference holds it. The compute dtype
/// is whatever the weights were loaded in — bfloat16, as the decoder is, for the same reason.
public final class LTX2VideoEncoder: Module {
    @ModuleInfo(key: "conv_in") var convIn: LTX2VideoConv3d
    @ModuleInfo(key: "down_blocks") var downBlocks: [Module]
    @ModuleInfo(key: "conv_out") var convOut: LTX2VideoConv3d
    @ModuleInfo(key: "per_channel_statistics") var statistics: LTX2EncoderStatistics

    public let layout: LTX2VideoEncoderLayout

    public init(_ layout: LTX2VideoEncoderLayout = .ltx25) {
        self.layout = layout
        let patched = layout.inputChannels * layout.patchSize * layout.patchSize
        _convIn.wrappedValue = LTX2VideoConv3d(
            inputChannels: patched, outputChannels: layout.stages[0].channels, causal: true)
        var blocks: [Module] = []
        for (index, stage) in layout.stages.enumerated() {
            if index > 0 {
                blocks.append(
                    LTX2SpaceToDepthDownsample(
                        inputChannels: layout.stages[index - 1].channels,
                        outputChannels: stage.channels,
                        stride: layout.strides[index - 1]))
            }
            blocks.append(LTX2ResnetStage(channels: stage.channels, blocks: stage.blocks, causal: true))
        }
        _downBlocks.wrappedValue = blocks
        _convOut.wrappedValue = LTX2VideoConv3d(
            inputChannels: layout.stages[layout.stages.count - 1].channels,
            outputChannels: layout.latentChannels + 1,
            causal: true)
        _statistics.wrappedValue = LTX2EncoderStatistics(channels: layout.latentChannels)
    }

    /// The dtype the encoder computes in: the one its weights hold.
    public var dtype: DType { convIn.conv.weight.dtype }

    /// Fills the tree from the pack's or a fixture's `vae_encoder.*` tensors. Every parameter
    /// must be covered exactly, for the reason `LTX2VideoDecoder.load` gives.
    public func load(weights: [String: MLXArray]) throws {
        try update(
            parameters: ModuleParameters.unflattened(LTX2VAEWeights.sanitizedEncoder(weights)),
            verify: .all)
    }

    /// Encodes pixels, `[1, 3, frames, height, width]` in the range -1 to 1, to a normalised
    /// latent `[1, channels, frames', height', width']` as the loop holds it.
    public func encode(_ pixels: MLXArray) -> MLXArray {
        var x = Self.patchified(pixels.transposed(0, 2, 3, 4, 1).asType(dtype), patch: layout.patchSize)
        x = convIn(x)
        for block in downBlocks {
            switch block {
            case let stage as LTX2ResnetStage: x = stage(x)
            case let downsample as LTX2SpaceToDepthDownsample: x = downsample(x)
            default: preconditionFailure("down_blocks holds only stages and downsamplers")
            }
        }
        x = convOut(silu(LTX2PixelNorm.apply(x)))
        return statistics.normalised(x[.ellipsis, 0..<layout.latentChannels])
            .transposed(0, 4, 1, 2, 3)
    }

    /// `[b, f, h·p, w·p, 3]` to `[b, f, h, w, 3·p·p]`, the exact inverse of
    /// `LTX2VideoDecoder.unpatchified`: the `p·p` channels of one colour run over the width
    /// offset first, then the height offset.
    static func patchified(_ x: MLXArray, patch p: Int) -> MLXArray {
        let (batch, frames, channels) = (x.dim(0), x.dim(1), x.dim(4))
        let (height, width) = (x.dim(2) / p, x.dim(3) / p)
        return x.reshaped([batch, frames, height, p, width, p, channels])
            .transposed(0, 1, 2, 4, 6, 5, 3)
            .reshaped([batch, frames, height, width, channels * p * p])
    }
}

import Foundation
import MLX
import MLXNN

/// The encoder half of the autoencoder: pixels in, the latent distribution's parameters out.
///
/// Unlike the decoder, whose stages are nested, the reference builds this one as a single flat
/// `down_blocks` list holding two different kinds of module — residual blocks and downsamplers,
/// interleaved. The checkpoint's keys are that flat list (`down_blocks.2.resample.1.weight` is a
/// downsampler; `down_blocks.3.conv1.weight` is a residual block), so the port is flat too.
/// Grouping it into stages would read better and would not load.
final class QwenImageVAEEncoder: Module {
    @ModuleInfo(key: "conv_in") var input: Conv2d
    @ModuleInfo(key: "down_blocks") var stages: [Module]
    @ModuleInfo(key: "mid_block") var middle: QwenImageVAEMidBlock
    @ModuleInfo(key: "norm_out") var outputNorm: QwenImageVAENorm
    @ModuleInfo(key: "conv_out") var output: Conv2d

    init(_ configuration: QwenImageVAEConfiguration, imageChannels: Int = 3) {
        // Widths run fine to coarse, the first repeated: [96, 96, 192, 384, 384] for the
        // shipped model. Each consecutive pair is one stage's input and output width.
        let widths = ([1] + configuration.dimMult).map { $0 * configuration.baseDim }

        _input.wrappedValue = Conv2d(
            inputChannels: imageChannels, outputChannels: widths[0],
            kernelSize: 3, padding: 1)

        var built: [Module] = []
        for index in 0..<(widths.count - 1) {
            var channels = widths[index]
            for _ in 0..<configuration.numResBlocks {
                built.append(
                    QwenImageVAEResidualBlock(
                        inputChannels: channels, outputChannels: widths[index + 1]))
                channels = widths[index + 1]
            }
            // Every stage but the last is followed by a downsampler.
            guard index != configuration.dimMult.count - 1 else { continue }
            built.append(
                QwenImageVAEDownsample(
                    channels: channels, halvesTime: configuration.temperalDownsample[index]))
        }
        _stages.wrappedValue = built

        let deepest = widths[widths.count - 1]
        _middle.wrappedValue = QwenImageVAEMidBlock(channels: deepest)
        _outputNorm.wrappedValue = QwenImageVAENorm(deepest, imagesOnly: false)
        // Twice the latent width: the encoder produces a mean and a log-variance per channel.
        _output.wrappedValue = Conv2d(
            inputChannels: deepest, outputChannels: configuration.zDim * 2,
            kernelSize: 3, padding: 1)
    }

    /// Encodes `[batch, height, width, 3]` into `[batch, height / 8, width / 8, zDim * 2]`.
    func callAsFunction(_ pixels: MLXArray) -> MLXArray {
        var h = input(pixels)
        for stage in stages {
            switch stage {
            case let block as QwenImageVAEResidualBlock: h = block(h)
            case let downsample as QwenImageVAEDownsample: h = downsample(h)
            default: preconditionFailure("unexpected module in the encoder's down_blocks")
            }
        }
        h = middle(h)
        return output(silu(outputNorm(h)))
    }
}

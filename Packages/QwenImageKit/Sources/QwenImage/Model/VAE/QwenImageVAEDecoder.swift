import Foundation
import MLX
import MLXNN

/// The decoder half of the autoencoder: latents in, pixels out.
final class QwenImageVAEDecoder: Module {
    @ModuleInfo(key: "conv_in") var input: Conv2d
    @ModuleInfo(key: "mid_block") var middle: QwenImageVAEMidBlock
    @ModuleInfo(key: "up_blocks") var stages: [QwenImageVAEUpBlock]
    @ModuleInfo(key: "norm_out") var outputNorm: QwenImageVAENorm
    @ModuleInfo(key: "conv_out") var output: Conv2d

    init(_ configuration: QwenImageVAEConfiguration, imageChannels: Int = 3) {
        // Widths run coarse to fine, starting from the deepest and repeating it once.
        let widths =
            ([configuration.dimMult.last ?? 1] + configuration.dimMult.reversed())
            .map { $0 * configuration.baseDim }
        // The encoder's time-halving stages, read backwards.
        let stretchesTime = Array(configuration.temperalDownsample.reversed())

        _input.wrappedValue = Conv2d(
            inputChannels: configuration.zDim, outputChannels: widths[0],
            kernelSize: 3, padding: 1)
        _middle.wrappedValue = QwenImageVAEMidBlock(channels: widths[0])

        var built: [QwenImageVAEUpBlock] = []
        for index in 0..<(widths.count - 1) {
            // Every stage but the first is fed by an upsampler, which halves the width.
            let inputChannels = index == 0 ? widths[index] : widths[index] / 2
            let last = index == configuration.dimMult.count - 1
            let upsample: QwenImageVAEUpBlock.Upsample? =
                last ? nil : (stretchesTime[index] ? .withTime : .spatialOnly)
            built.append(
                QwenImageVAEUpBlock(
                    inputChannels: inputChannels,
                    outputChannels: widths[index + 1],
                    residualBlocks: configuration.numResBlocks,
                    upsample: upsample
                ))
        }
        _stages.wrappedValue = built

        let finalWidth = widths[widths.count - 1]
        _outputNorm.wrappedValue = QwenImageVAENorm(finalWidth, imagesOnly: false)
        _output.wrappedValue = Conv2d(
            inputChannels: finalWidth, outputChannels: imageChannels,
            kernelSize: 3, padding: 1)
    }

    /// Decodes `[batch, height, width, latentChannels]` into `[batch, height, width, 3]`.
    func callAsFunction(_ latents: MLXArray) -> MLXArray {
        var h = middle(input(latents))
        for stage in stages { h = stage(h) }
        return output(silu(outputNorm(h)))
    }
}

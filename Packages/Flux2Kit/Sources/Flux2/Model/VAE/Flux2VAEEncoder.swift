import Foundation
import MLX
import MLXNN

/// The encoder half: pixels in, the posterior's parameters out.
///
/// `conv_out` writes twice the latent width — the mean and the log-variance of a diagonal
/// Gaussian, stacked on the channel axis in that order. Splitting them is the caller's job,
/// because only the caller knows whether it wants a sample or the mean.
final class Flux2VAEEncoder: Module {
    @ModuleInfo(key: "conv_in") var input: Conv2d
    @ModuleInfo(key: "down_blocks") var stages: [Flux2VAEDownBlock]
    @ModuleInfo(key: "mid_block") var middle: Flux2VAEMidBlock
    @ModuleInfo(key: "conv_norm_out") var outputNorm: GroupNorm
    @ModuleInfo(key: "conv_out") var output: Conv2d

    init(_ configuration: Flux2VAEConfiguration, imageChannels: Int = 3) {
        let widths = configuration.blockOutChannels
        let groups = configuration.normNumGroups
        let deepest = widths[widths.count - 1]

        _input.wrappedValue = Conv2d(
            inputChannels: imageChannels, outputChannels: widths[0], kernelSize: 3, padding: 1)
        _stages.wrappedValue = widths.indices.map { index in
            Flux2VAEDownBlock(
                inputChannels: index == 0 ? widths[0] : widths[index - 1],
                outputChannels: widths[index],
                layers: configuration.layersPerBlock,
                groups: groups,
                halves: index != widths.count - 1)
        }
        _middle.wrappedValue = Flux2VAEMidBlock(channels: deepest, groups: groups)
        _outputNorm.wrappedValue = .flux2(channels: deepest, groups: groups)
        _output.wrappedValue = Conv2d(
            inputChannels: deepest, outputChannels: 2 * configuration.latentChannels,
            kernelSize: 3, padding: 1)
    }

    /// Encodes `[batch, height, width, 3]` into `[batch, height / 8, width / 8, 2 * latent]`.
    func callAsFunction(_ image: MLXArray) -> MLXArray {
        var h = input(image)
        for stage in stages { h = stage(h) }
        h = middle(h)
        return output(silu(outputNorm(h)))
    }
}

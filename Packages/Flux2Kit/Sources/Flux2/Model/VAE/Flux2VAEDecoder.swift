import Foundation
import MLX
import MLXNN

/// The decoder half: latents in, pixels out.
///
/// The widths run coarse to fine, the encoder's list read backwards, and the stage boundaries
/// are where the checkpoint's `conv_shortcut` weights appear.
final class Flux2VAEDecoder: Module {
    @ModuleInfo(key: "conv_in") var input: Conv2d
    @ModuleInfo(key: "mid_block") var middle: Flux2VAEMidBlock
    @ModuleInfo(key: "up_blocks") var stages: [Flux2VAEUpBlock]
    @ModuleInfo(key: "conv_norm_out") var outputNorm: GroupNorm
    @ModuleInfo(key: "conv_out") var output: Conv2d

    init(_ configuration: Flux2VAEConfiguration, imageChannels: Int = 3) {
        let widths = Array(configuration.blockOutChannels.reversed())
        let groups = configuration.normNumGroups
        let finest = widths[widths.count - 1]

        _input.wrappedValue = Conv2d(
            inputChannels: configuration.latentChannels, outputChannels: widths[0],
            kernelSize: 3, padding: 1)
        _middle.wrappedValue = Flux2VAEMidBlock(channels: widths[0], groups: groups)
        _stages.wrappedValue = widths.indices.map { index in
            Flux2VAEUpBlock(
                inputChannels: index == 0 ? widths[0] : widths[index - 1],
                outputChannels: widths[index],
                // One more than the encoder's stages carry, which diffusers writes as
                // `layers_per_block + 1`; the checkpoint's three resnets per stage agree.
                layers: configuration.layersPerBlock + 1,
                groups: groups,
                doubles: index != widths.count - 1)
        }
        _outputNorm.wrappedValue = .flux2(channels: finest, groups: groups)
        _output.wrappedValue = Conv2d(
            inputChannels: finest, outputChannels: imageChannels, kernelSize: 3, padding: 1)
    }

    /// Decodes `[batch, height, width, latent]` into `[batch, height * 8, width * 8, 3]`.
    func callAsFunction(_ latents: MLXArray) -> MLXArray {
        var h = middle(input(latents))
        for stage in stages { h = stage(h) }
        return output(silu(outputNorm(h)))
    }
}

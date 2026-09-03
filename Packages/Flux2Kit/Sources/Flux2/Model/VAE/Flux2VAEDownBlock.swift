import Foundation
import MLX
import MLXNN

/// One stage of the encoder: a few residual blocks, then optionally a halving.
///
/// The deepest stage has no downsampler, which is why the checkpoint carries `downsamplers` for
/// three of the four stages.
final class Flux2VAEDownBlock: Module {
    @ModuleInfo(key: "resnets") var resnets: [Flux2VAEResnetBlock]
    @ModuleInfo(key: "downsamplers") var downsamplers: [Flux2VAEDownsample]

    init(inputChannels: Int, outputChannels: Int, layers: Int, groups: Int, halves: Bool) {
        var channels = inputChannels
        _resnets.wrappedValue = (0..<layers).map { _ in
            let block = Flux2VAEResnetBlock(
                inputChannels: channels, outputChannels: outputChannels, groups: groups)
            channels = outputChannels
            return block
        }
        _downsamplers.wrappedValue = halves ? [Flux2VAEDownsample(channels: outputChannels)] : []
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = x
        for resnet in resnets { h = resnet(h) }
        return downsamplers.first.map { $0(h) } ?? h
    }
}

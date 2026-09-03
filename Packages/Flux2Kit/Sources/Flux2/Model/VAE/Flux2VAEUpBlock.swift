import Foundation
import MLX
import MLXNN

/// One stage of the decoder: a few residual blocks, then optionally a doubling.
///
/// A decoder stage carries one more residual block than the encoder stage it mirrors —
/// diffusers passes `layers_per_block + 1` here — and the finest stage has no upsampler.
final class Flux2VAEUpBlock: Module {
    @ModuleInfo(key: "resnets") var resnets: [Flux2VAEResnetBlock]
    @ModuleInfo(key: "upsamplers") var upsamplers: [Flux2VAEUpsample]

    init(inputChannels: Int, outputChannels: Int, layers: Int, groups: Int, doubles: Bool) {
        var channels = inputChannels
        _resnets.wrappedValue = (0..<layers).map { _ in
            let block = Flux2VAEResnetBlock(
                inputChannels: channels, outputChannels: outputChannels, groups: groups)
            channels = outputChannels
            return block
        }
        _upsamplers.wrappedValue = doubles ? [Flux2VAEUpsample(channels: outputChannels)] : []
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = x
        for resnet in resnets { h = resnet(h) }
        return upsamplers.first.map { $0(h) } ?? h
    }
}

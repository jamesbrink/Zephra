import Foundation
import MLX
import MLXNN

/// One stage of the decoder: a few residual blocks, then optionally an upsample.
///
/// The last stage has no upsampler, which is why the checkpoint carries `upsamplers` for three
/// of the four.
final class QwenImageVAEUpBlock: Module {
    @ModuleInfo(key: "resnets") var resnets: [QwenImageVAEResidualBlock]
    @ModuleInfo(key: "upsamplers") var upsamplers: [QwenImageVAEUpsample]

    init(inputChannels: Int, outputChannels: Int, residualBlocks: Int, upsample: Upsample?) {
        var channels = inputChannels
        _resnets.wrappedValue = (0...residualBlocks).map { _ in
            let block = QwenImageVAEResidualBlock(
                inputChannels: channels, outputChannels: outputChannels)
            channels = outputChannels
            return block
        }
        _upsamplers.wrappedValue = upsample.map {
            [QwenImageVAEUpsample(channels: outputChannels, stretchesTime: $0 == .withTime)]
        } ?? []
    }

    /// Whether a stage's upsampler also stretches the time axis. It never matters for a still
    /// image, but it decides which weights the stage carries.
    enum Upsample {
        case spatialOnly
        case withTime
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = x
        for resnet in resnets { h = resnet(h) }
        return upsamplers.first.map { $0(h) } ?? h
    }
}

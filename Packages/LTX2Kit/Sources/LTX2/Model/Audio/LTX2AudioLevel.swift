import Foundation
import MLX
import MLXNN

/// One level of the audio decoder: its residual blocks, the first taking the level above's
/// width, and the doubling upsampler that follows every level but the lowest.
final class LTX2AudioLevel: Module {
    @ModuleInfo(key: "block") var blocks: [LTX2AudioResnetBlock]
    @ModuleInfo(key: "upsample") var upsample: LTX2AudioUpsample?

    init(inputChannels: Int, channels: Int, blocks: Int, upsamples: Bool, eps: Float) {
        _blocks.wrappedValue = (0..<blocks).map { index in
            LTX2AudioResnetBlock(
                inputChannels: index == 0 ? inputChannels : channels, outputChannels: channels, eps: eps)
        }
        _upsample.wrappedValue = upsamples ? LTX2AudioUpsample(channels: channels) : nil
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = x
        for block in blocks { h = block(h) }
        return upsample.map { $0(h) } ?? h
    }
}

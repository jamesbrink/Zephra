import Foundation
import MLX
import MLXNN

/// The decoder's middle: a residual block, the one attention, and another residual block.
final class QwenImageVAEMidBlock: Module {
    @ModuleInfo(key: "resnets") var resnets: [QwenImageVAEResidualBlock]
    @ModuleInfo(key: "attentions") var attentions: [QwenImageVAEAttentionBlock]

    init(channels: Int) {
        _resnets.wrappedValue = (0..<2).map { _ in
            QwenImageVAEResidualBlock(inputChannels: channels, outputChannels: channels)
        }
        _attentions.wrappedValue = [QwenImageVAEAttentionBlock(channels)]
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = resnets[0](x)
        for (attention, resnet) in zip(attentions, resnets.dropFirst()) {
            h = resnet(attention(h))
        }
        return h
    }
}

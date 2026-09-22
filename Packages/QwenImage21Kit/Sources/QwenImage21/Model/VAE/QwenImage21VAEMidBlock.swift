import Foundation
import MLX
import MLXNN

/// The narrowest point of either half: a residual block, then attention over the picture, then
/// another residual block.
///
/// `num_layers` is one in every published configuration, so there is one attention block and
/// two residual ones; the loop keeps the reference's shape so a wider mid block would be a
/// number and not a rewrite.
final class QwenImage21VAEMidBlock: Module {
    @ModuleInfo(key: "resnets") var resnets: [QwenImage21ResidualBlock]
    @ModuleInfo(key: "attentions") var attentions: [QwenImage21VAEAttentionBlock]

    init(channels: Int, layers: Int = 1) {
        _resnets.wrappedValue = (0...layers).map { _ in
            QwenImage21ResidualBlock(inputChannels: channels, outputChannels: channels)
        }
        _attentions.wrappedValue = (0..<layers).map { _ in
            QwenImage21VAEAttentionBlock(channels: channels)
        }
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var x = resnets[0](x)
        for (attention, resnet) in zip(attentions, resnets.dropFirst()) {
            x = resnet(attention(x))
        }
        return x
    }
}

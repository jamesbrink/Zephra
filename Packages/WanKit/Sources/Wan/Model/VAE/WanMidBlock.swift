import Foundation
import MLX
import MLXNN

/// The narrowest point of either half: a residual block, then attention over each frame,
/// then another residual block.
///
/// `num_layers` is one in every Wan configuration, so there is one attention block and two
/// residual ones; the loop is kept in the reference's shape so a wider mid block would be a
/// number and not a rewrite.
final class WanMidBlock: Module {
    @ModuleInfo(key: "resnets") var resnets: [WanResidualBlock]
    @ModuleInfo(key: "attentions") var attentions: [WanAttentionBlock]

    init(channels: Int, layers: Int = 1) {
        _resnets.wrappedValue = (0...layers).map { _ in
            WanResidualBlock(inputChannels: channels, outputChannels: channels)
        }
        _attentions.wrappedValue = (0..<layers).map { _ in WanAttentionBlock(channels: channels) }
    }

    func callAsFunction(_ x: MLXArray, cache: WanFeatureCache) -> MLXArray {
        var x = resnets[0](x, cache: cache)
        for (attention, resnet) in zip(attentions, resnets.dropFirst()) {
            x = resnet(attention(x), cache: cache)
        }
        return x
    }
}

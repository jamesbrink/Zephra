import Foundation
import MLX
import MLXNN

/// The middle of either tower: a residual block, the one attention, another residual block.
///
/// Both towers build the same shape at the same width, which is why one type serves both.
final class Flux2VAEMidBlock: Module {
    @ModuleInfo(key: "resnets") var resnets: [Flux2VAEResnetBlock]
    @ModuleInfo(key: "attentions") var attentions: [Flux2VAEAttentionBlock]

    init(channels: Int, groups: Int) {
        _resnets.wrappedValue = (0..<2).map { _ in
            Flux2VAEResnetBlock(
                inputChannels: channels, outputChannels: channels, groups: groups)
        }
        _attentions.wrappedValue = [
            Flux2VAEAttentionBlock(channels: channels, groups: groups)
        ]
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = resnets[0](x)
        for (attention, resnet) in zip(attentions, resnets.dropFirst()) {
            h = resnet(attention(h))
        }
        return h
    }
}

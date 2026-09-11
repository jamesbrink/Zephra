import Foundation
import MLX
import MLXNN

/// The two residual blocks between the audio decoder's first convolution and its levels.
/// No attention between them: `mid_block_add_attention` is off in this checkpoint.
final class LTX2AudioMiddle: Module {
    @ModuleInfo(key: "block_1") var first: LTX2AudioResnetBlock
    @ModuleInfo(key: "block_2") var second: LTX2AudioResnetBlock

    init(channels: Int, eps: Float) {
        _first.wrappedValue = LTX2AudioResnetBlock(inputChannels: channels, outputChannels: channels, eps: eps)
        _second.wrappedValue = LTX2AudioResnetBlock(inputChannels: channels, outputChannels: channels, eps: eps)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray { second(first(x)) }
}

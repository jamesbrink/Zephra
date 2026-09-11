import Foundation
import MLX
import MLXNN

/// One of the vocoder's residual blocks: three dilated paths of activation, convolution,
/// activation, convolution, each added back in turn (BigVGAN's `AMPBlock1`).
///
/// `convs1` dilate by 1, 3 and 5 at the block's kernel; `convs2` do not dilate. Every
/// convolution keeps the length, padded by `dilation * (kernel - 1) / 2` a side.
final class LTX2VocoderResBlock: Module {
    @ModuleInfo(key: "convs1") var dilated: [Conv1d]
    @ModuleInfo(key: "convs2") var plain: [Conv1d]
    @ModuleInfo(key: "acts1") var firstActivations: [LTX2AntiAliasedActivation]
    @ModuleInfo(key: "acts2") var secondActivations: [LTX2AntiAliasedActivation]

    static let dilations = [1, 3, 5]

    init(channels: Int, kernel: Int) {
        _dilated.wrappedValue = Self.dilations.map { dilation in
            Conv1d(
                inputChannels: channels, outputChannels: channels, kernelSize: kernel,
                padding: dilation * (kernel - 1) / 2, dilation: dilation)
        }
        _plain.wrappedValue = Self.dilations.map { _ in
            Conv1d(inputChannels: channels, outputChannels: channels, kernelSize: kernel, padding: (kernel - 1) / 2)
        }
        _firstActivations.wrappedValue = Self.dilations.map { _ in LTX2AntiAliasedActivation(channels: channels) }
        _secondActivations.wrappedValue = Self.dilations.map { _ in LTX2AntiAliasedActivation(channels: channels) }
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = x
        for index in Self.dilations.indices {
            var path = dilated[index](firstActivations[index](h))
            path = plain[index](secondActivations[index](path))
            h = h + path
        }
        return h
    }
}

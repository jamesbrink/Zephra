import Foundation
import MLX
import MLXNN

/// One BigVGAN generator: a mel spectrogram in, a waveform out, through a stack of
/// transposed convolutions each followed by three residual blocks averaged.
///
/// Two of these make LTX-2.5's vocoder: the first turns the decoder's mel into a 16 kHz
/// waveform, the second (`bwe_generator`) turns a mel of that waveform into the residual
/// that extends its bandwidth to 48 kHz. Each halves its width at every upsampler, from
/// `hiddenChannels` down; the last activation is anti-aliased like the blocks' and the last
/// convolution carries no bias.
final class LTX2VocoderGenerator: Module {
    @ModuleInfo(key: "conv_pre") var convIn: Conv1d
    @ModuleInfo(key: "ups") var upsamplers: [ConvTransposed1d]
    @ModuleInfo(key: "resblocks") var blocks: [LTX2VocoderResBlock]
    @ModuleInfo(key: "act_post") var activationOut: LTX2AntiAliasedActivation
    @ModuleInfo(key: "conv_post") var convOut: Conv1d

    static let blockKernels = [3, 7, 11]

    let layout: LTX2VocoderGeneratorLayout

    init(_ layout: LTX2VocoderGeneratorLayout) {
        self.layout = layout
        _convIn.wrappedValue = Conv1d(
            inputChannels: layout.inputChannels, outputChannels: layout.hiddenChannels, kernelSize: 7, padding: 3)
        var width = layout.hiddenChannels
        var ups: [ConvTransposed1d] = []
        var blocks: [LTX2VocoderResBlock] = []
        for (kernel, factor) in zip(layout.kernels, layout.factors) {
            ups.append(
                ConvTransposed1d(
                    inputChannels: width, outputChannels: width / 2, kernelSize: kernel,
                    stride: factor, padding: (kernel - factor) / 2))
            width /= 2
            blocks += Self.blockKernels.map { LTX2VocoderResBlock(channels: width, kernel: $0) }
        }
        _upsamplers.wrappedValue = ups
        _blocks.wrappedValue = blocks
        _activationOut.wrappedValue = LTX2AntiAliasedActivation(channels: width)
        _convOut.wrappedValue = Conv1d(
            inputChannels: width, outputChannels: layout.outputChannels, kernelSize: 7, padding: 3, bias: false)
    }

    /// A mel `[batch, frames, inputChannels]` to a waveform `[batch, samples, outputChannels]`,
    /// `samples` being the frames times the upsampling.
    func callAsFunction(_ mel: MLXArray) -> MLXArray {
        var x = convIn(mel)
        let perStage = Self.blockKernels.count
        for (stage, upsampler) in upsamplers.enumerated() {
            x = upsampler(x)
            let outputs = (0..<perStage).map { blocks[stage * perStage + $0](x) }
            x = outputs.dropFirst().reduce(outputs[0], +) / Float(perStage)
        }
        return convOut(activationOut(x))
    }
}

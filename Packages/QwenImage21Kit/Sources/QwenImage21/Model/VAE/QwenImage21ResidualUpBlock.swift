import Foundation
import MLX
import MLXNN

/// One decoder stage, `QwenImage21ResidualUpBlock`: one more residual block than the encoder's
/// stage, the upsampler after them, and the input duplicated up and added around the whole
/// stage.
///
/// Stages 0 to 3 double and stage 4 does not. The last stage has neither an upsampler nor a
/// shortcut -- the reference leaves both out rather than building identities, and the
/// checkpoint has nothing under `up_blocks.4.upsampler`.
final class QwenImage21ResidualUpBlock: Module {
    @ModuleInfo(key: "resnets") var resnets: [QwenImage21ResidualBlock]
    @ModuleInfo(key: "upsampler") var upsampler: QwenImage21Upsample?

    let shortcut: QwenImage21DupUp?

    init(
        inputChannels: Int, outputChannels: Int, blocks: Int, doublesSpace: Bool,
        unfoldsTime: Bool
    ) {
        shortcut =
            doublesSpace
            ? QwenImage21DupUp(
                inputChannels: inputChannels, outputChannels: outputChannels,
                temporalFactor: unfoldsTime ? 2 : 1, spatialFactor: 2)
            : nil
        _resnets.wrappedValue = (0...blocks).map { index in
            QwenImage21ResidualBlock(
                inputChannels: index == 0 ? inputChannels : outputChannels,
                outputChannels: outputChannels)
        }
        _upsampler.wrappedValue =
            doublesSpace ? QwenImage21Upsample(channels: outputChannels) : nil
        super.init()
    }

    /// The residual blocks and the upsampler are each evaluated before the next thing is built
    /// on them, which bounds the stage's peak at the upsampler's one convolution rather than at
    /// everything the stage computes; `QwenImage21VAEDecoder` has the measurement.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = resnets.reduce(x) { $1($0) }
        eval(h)
        if let upsampler {
            h = upsampler(h)
            eval(h)
        }
        if let shortcut {
            h = h + shortcut(x)
        }
        return h
    }
}

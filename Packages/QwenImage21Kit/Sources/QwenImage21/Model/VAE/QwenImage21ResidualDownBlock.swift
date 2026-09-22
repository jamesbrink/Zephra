import Foundation
import MLX
import MLXNN

/// One encoder stage, `QwenImage21ResidualDownBlock`: the residual blocks and the downsampler
/// after them, with the input averaged down and added around the whole stage.
///
/// The first block changes the width and the rest keep it. Stages 0 to 3 halve, stage 4 does
/// not, and four halvings are the autoencoder's sixteen. The last stage still has a shortcut,
/// an average over groups of one and so the identity; the reference builds it the same way and
/// so does this, so every stage reads alike.
final class QwenImage21ResidualDownBlock: Module {
    @ModuleInfo(key: "resnets") var resnets: [QwenImage21ResidualBlock]
    @ModuleInfo(key: "downsampler") var downsampler: QwenImage21Downsample?

    let shortcut: QwenImage21AvgDown

    init(inputChannels: Int, outputChannels: Int, blocks: Int, halvesSpace: Bool, foldsTime: Bool)
    {
        shortcut = QwenImage21AvgDown(
            inputChannels: inputChannels, outputChannels: outputChannels,
            temporalFactor: foldsTime ? 2 : 1, spatialFactor: halvesSpace ? 2 : 1)
        _resnets.wrappedValue = (0..<blocks).map { index in
            QwenImage21ResidualBlock(
                inputChannels: index == 0 ? inputChannels : outputChannels,
                outputChannels: outputChannels)
        }
        _downsampler.wrappedValue =
            halvesSpace ? QwenImage21Downsample(channels: outputChannels) : nil
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = resnets.reduce(x) { $1($0) }
        if let downsampler {
            h = downsampler(h)
        }
        return h + shortcut(x)
    }
}

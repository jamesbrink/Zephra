import Foundation
import MLX
import MLXNN

/// One encoder stage of the residual layout: the residual blocks and the downsampler after
/// them, with the input averaged down and added around the whole stage.
///
/// The first block changes the width and the rest keep it. The last stage has no downsampler
/// and its shortcut is the identity, an average over groups of one; the reference builds it
/// the same way and so does this, so every stage reads alike.
final class WanResidualDownBlock: Module {
    @ModuleInfo(key: "resnets") var resnets: [WanResidualBlock]
    @ModuleInfo(key: "downsampler") var downsampler: WanResample?

    let shortcut: WanAvgDown3D

    init(inputChannels: Int, outputChannels: Int, blocks: Int, halvesSpace: Bool, halvesTime: Bool) {
        shortcut = WanAvgDown3D(
            inputChannels: inputChannels, outputChannels: outputChannels,
            temporalFactor: halvesTime ? 2 : 1, spatialFactor: halvesSpace ? 2 : 1)
        _resnets.wrappedValue = (0..<blocks).map { index in
            WanResidualBlock(
                inputChannels: index == 0 ? inputChannels : outputChannels, outputChannels: outputChannels)
        }
        _downsampler.wrappedValue = halvesSpace
            ? WanResample(channels: outputChannels, mode: halvesTime ? .downsample3d : .downsample2d)
            : nil
        super.init()
    }

    func callAsFunction(_ x: MLXArray, cache: WanFeatureCache) -> MLXArray {
        var h = resnets.reduce(x) { $1($0, cache: cache) }
        if let downsampler {
            h = downsampler(h, cache: cache)
        }
        return h + shortcut(x)
    }
}

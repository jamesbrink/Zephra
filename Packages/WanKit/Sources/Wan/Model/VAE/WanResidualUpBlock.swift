import Foundation
import MLX
import MLXNN

/// One decoder stage of the residual layout: one more residual block than the encoder's
/// stage, the upsampler after them, and the input duplicated up and added around the whole
/// stage.
///
/// The last stage neither upsamples nor has a shortcut; the reference leaves both out rather
/// than building an identity, and the checkpoint has nothing under `up_blocks.3.upsampler`.
final class WanResidualUpBlock: Module {
    @ModuleInfo(key: "resnets") var resnets: [WanResidualBlock]
    @ModuleInfo(key: "upsampler") var upsampler: WanResample?

    let shortcut: WanDupUp3D?

    init(inputChannels: Int, outputChannels: Int, blocks: Int, doublesSpace: Bool, doublesTime: Bool) {
        shortcut = doublesSpace
            ? WanDupUp3D(
                inputChannels: inputChannels, outputChannels: outputChannels,
                temporalFactor: doublesTime ? 2 : 1, spatialFactor: 2)
            : nil
        _resnets.wrappedValue = (0...blocks).map { index in
            WanResidualBlock(
                inputChannels: index == 0 ? inputChannels : outputChannels, outputChannels: outputChannels)
        }
        _upsampler.wrappedValue = doublesSpace
            ? WanResample(channels: outputChannels, mode: doublesTime ? .upsample3d : .upsample2d)
            : nil
        super.init()
    }

    func callAsFunction(_ x: MLXArray, cache: WanFeatureCache, firstChunk: Bool) -> MLXArray {
        var h = resnets.reduce(x) { $1($0, cache: cache) }
        if let upsampler {
            h = upsampler(h, cache: cache)
        }
        if let shortcut {
            h = h + shortcut(x, firstChunk: firstChunk)
        }
        return h
    }
}

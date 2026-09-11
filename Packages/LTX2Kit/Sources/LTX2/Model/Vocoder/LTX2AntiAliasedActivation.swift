import Foundation
import MLX
import MLXNN

/// An activation that does not alias: the signal doubled, the Snake applied, and the result
/// halved, so the harmonics the nonlinearity creates above the Nyquist rate are filtered out
/// rather than folded back in (BigVGAN's `Activation1d`).
final class LTX2AntiAliasedActivation: Module {
    @ModuleInfo(key: "upsample") var upsample: LTX2SincUpsample
    @ModuleInfo(key: "act") var activation: LTX2SnakeBeta
    @ModuleInfo(key: "downsample") var downsample: LTX2SincDownsample

    init(channels: Int) {
        _upsample.wrappedValue = LTX2SincUpsample()
        _activation.wrappedValue = LTX2SnakeBeta(channels: channels)
        _downsample.wrappedValue = LTX2SincDownsample()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        downsample(activation(upsample(x)))
    }
}

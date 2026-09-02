import Foundation
import MLX
import MLXNN

/// Doubles both spatial axes and halves the width.
///
/// `timeConv` is loaded and never used. The reference has two upsample modes, one of which also
/// stretches the time axis, and the checkpoint carries its weights for the first two stages. A
/// still image is one frame, and the reference itself skips that convolution for the first frame
/// of a sequence, so it would be a no-op here. It stays in the tree so the weights have somewhere
/// to land and nothing is silently unaccounted for.
final class QwenImageVAEUpsample: Module {
    @ModuleInfo(key: "resample") var resample: [Module]
    @ModuleInfo(key: "time_conv") var timeConv: Conv2d?

    init(channels: Int, stretchesTime: Bool) {
        // Slot 0 is the reference's nearest-neighbour scaler, which carries no weights.
        _resample.wrappedValue = [
            Identity(),
            Conv2d(
                inputChannels: channels, outputChannels: channels / 2,
                kernelSize: 3, padding: 1),
        ]
        _timeConv.wrappedValue =
            stretchesTime
            ? Conv2d(inputChannels: channels, outputChannels: channels * 2, kernelSize: 1)
            : nil
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        guard let convolution = resample[1] as? Conv2d else {
            preconditionFailure("the resampler's slot 1 must be its convolution")
        }
        return convolution(Self.nearestDoubled(x))
    }

    /// Nearest-neighbour doubling of height and width, which is what `nearest-exact` at a scale
    /// of two comes to.
    static func nearestDoubled(_ x: MLXArray) -> MLXArray {
        let (batch, height, width, channels) = (x.shape[0], x.shape[1], x.shape[2], x.shape[3])
        return
            MLX.broadcast(
                x.reshaped([batch, height, 1, width, 1, channels]),
                to: [batch, height, 2, width, 2, channels]
            )
            .reshaped([batch, height * 2, width * 2, channels])
    }
}

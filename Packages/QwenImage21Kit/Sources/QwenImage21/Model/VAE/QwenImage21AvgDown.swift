import Foundation
import MLX

/// The shortcut around an encoder stage, `QwenImage21AvgDown3D`: the input folded down to the
/// stage's output size by averaging, with no weights. `is_residual: true` is what selects it.
///
/// The reference folds the frame offset and the two spatial offsets into the channel axis --
/// for one input channel the folded channels run over the time offset, then the row, then the
/// column -- and averages contiguous groups of those down to the output width. A chunk whose
/// frame count is not a multiple of the temporal factor is **zero-padded at the front** first.
///
/// For a still image that front pad is the whole of the temporal half, and it is not a
/// no-op: with `factor_t = 2` the one real frame pairs with a frame of zeros that comes
/// **before** it, so half of every group is zeros and each output channel comes back at half
/// the average of its 2 x 2 block, with the other half of the channels zero outright. That is
/// the reference's arithmetic, not an approximation of it, and a port that quietly skipped the
/// pad would double the shortcut's contribution at three of the five encoder stages.
struct QwenImage21AvgDown {
    let outputChannels: Int
    let temporalFactor: Int
    let spatialFactor: Int
    /// Folded channels averaged into one output channel.
    let groupSize: Int

    init(inputChannels: Int, outputChannels: Int, temporalFactor: Int, spatialFactor: Int) {
        let factor = temporalFactor * spatialFactor * spatialFactor
        precondition(
            inputChannels * factor % outputChannels == 0, "the folded channels group evenly")
        self.outputChannels = outputChannels
        self.temporalFactor = temporalFactor
        self.spatialFactor = spatialFactor
        groupSize = inputChannels * factor / outputChannels
    }

    /// `[batch, height, width, channels]` to `[batch, height / s, width / s, out]`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let (t, s) = (temporalFactor, spatialFactor)
        let batch = x.dim(0)
        let (height, width, channels) = (x.dim(1) / s, x.dim(2) / s, x.dim(3))
        // [b, h', sh, w', sw, c] to [b, h', w', c, sh, sw], the reference's channel order with
        // the time offset still to come between the channel and the row.
        var folded = x.reshaped([batch, height, s, width, s, channels])
            .transposed(0, 1, 3, 5, 2, 4)
            .reshaped([batch, height, width, channels, 1, s, s])
        if t > 1 {
            // The real frame is last, because the reference pads the front of the time axis.
            folded = padded(folded, widths: [0, 0, 0, 0, [t - 1, 0], 0, 0])
        }
        return mean(
            folded.reshaped([batch, height, width, outputChannels, groupSize]), axis: -1)
    }
}

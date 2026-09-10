import Foundation
import MLX

/// The shortcut around an encoder stage: the input folded down to the stage's output size by
/// averaging, with no weights, `AvgDown3D` in the reference.
///
/// Time and space are folded into the channel axis -- for one input channel the folded
/// channels run over the time offset, then the row, then the column -- and contiguous groups
/// of the folded channels are averaged down to the output width. A chunk whose frame count
/// is not a multiple of the temporal factor is zero-padded at the front first, which is how a
/// single first frame folds by two: it pairs with a frame of zeros.
struct WanAvgDown3D {
    let outputChannels: Int
    let temporalFactor: Int
    let spatialFactor: Int
    /// Folded channels averaged into one output channel.
    let groupSize: Int

    init(inputChannels: Int, outputChannels: Int, temporalFactor: Int, spatialFactor: Int) {
        let factor = temporalFactor * spatialFactor * spatialFactor
        precondition(inputChannels * factor % outputChannels == 0, "the folded channels group evenly")
        self.outputChannels = outputChannels
        self.temporalFactor = temporalFactor
        self.spatialFactor = spatialFactor
        groupSize = inputChannels * factor / outputChannels
    }

    /// `[b, f, h, w, c]` to `[b, f / t, h / s, w / s, out]`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var x = x
        let (t, s) = (temporalFactor, spatialFactor)
        let missing = (t - x.dim(1) % t) % t
        if missing > 0 {
            x = padded(x, widths: [0, [missing, 0], 0, 0, 0])
        }
        let (batch, channels) = (x.dim(0), x.dim(4))
        let (frames, height, width) = (x.dim(1) / t, x.dim(2) / s, x.dim(3) / s)
        x = x.reshaped([batch, frames, t, height, s, width, s, channels])
            .transposed(0, 1, 3, 5, 7, 2, 4, 6)
            .reshaped([batch, frames, height, width, outputChannels, groupSize])
        return mean(x, axis: -1)
    }
}

import Foundation
import MLX

/// The shortcut around a decoder stage, `QwenImage21DupUp3D`: the input stretched to the
/// stage's output size by repeating, with no weights, and the inverse of `QwenImage21AvgDown`.
///
/// Each input channel is repeated in place until there are enough channels to unfold, and the
/// unfold runs the way the fold does -- for one output channel the channels run over the time
/// offset, then the row, then the column. On the first chunk the frames the temporal repeat put
/// **in front of** the first frame are dropped, `x[:, :, factor_t - 1:]`, and a still image is
/// always a first chunk, so what survives is the last time offset alone.
///
/// Which offset survives is the whole of the temporal half here, and it is not cosmetic. Where
/// the stage keeps its width the repeats are all copies of one channel and the result is a
/// plain nearest-neighbour doubling; where the stage halves its width they are not, and the
/// surviving offset picks out the **odd** input channels. A port that dropped the time axis by
/// slicing the wrong end would hand the next stage a picture built from the even ones, which
/// looks like a picture and is the wrong one.
struct QwenImage21DupUp {
    let outputChannels: Int
    let temporalFactor: Int
    let spatialFactor: Int
    /// Copies of each input channel the unfold consumes.
    let repeats: Int

    init(inputChannels: Int, outputChannels: Int, temporalFactor: Int, spatialFactor: Int) {
        let factor = temporalFactor * spatialFactor * spatialFactor
        precondition(
            outputChannels * factor % inputChannels == 0, "the repeated channels unfold evenly")
        self.outputChannels = outputChannels
        self.temporalFactor = temporalFactor
        self.spatialFactor = spatialFactor
        repeats = outputChannels * factor / inputChannels
    }

    /// `[batch, height, width, channels]` to `[batch, height * s, width * s, out]`, on the
    /// first and only chunk.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let (t, s) = (temporalFactor, spatialFactor)
        let (batch, height, width) = (x.dim(0), x.dim(1), x.dim(2))
        return repeated(x, count: repeats, axis: -1)
            .reshaped([batch, height, width, outputChannels, t, s, s])[
                0..., 0..., 0..., 0..., t - 1]
            .transposed(0, 1, 4, 2, 5, 3)
            .reshaped([batch, height * s, width * s, outputChannels])
    }
}

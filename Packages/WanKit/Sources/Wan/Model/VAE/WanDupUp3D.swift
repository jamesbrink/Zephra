import Foundation
import MLX

/// The shortcut around a decoder stage: the input stretched to the stage's output size by
/// repeating, with no weights, `DupUp3D` in the reference and the inverse of `WanAvgDown3D`.
///
/// Each input channel is repeated in place until there are enough channels to unfold, and the
/// unfold runs the same way as the fold -- for one output channel the channels run over the
/// time offset, then the row, then the column. On the first chunk the frames the temporal
/// repeat put in front of the first frame are dropped, so one latent frame stretches to one
/// pixel frame there and to two everywhere after, which matches what the upsampler beside it
/// does by skipping its `time_conv`.
struct WanDupUp3D {
    let outputChannels: Int
    let temporalFactor: Int
    let spatialFactor: Int
    /// Copies of each input channel the unfold consumes.
    let repeats: Int

    init(inputChannels: Int, outputChannels: Int, temporalFactor: Int, spatialFactor: Int) {
        let factor = temporalFactor * spatialFactor * spatialFactor
        precondition(outputChannels * factor % inputChannels == 0, "the repeated channels unfold evenly")
        self.outputChannels = outputChannels
        self.temporalFactor = temporalFactor
        self.spatialFactor = spatialFactor
        repeats = outputChannels * factor / inputChannels
    }

    /// `[b, f, h, w, c]` to `[b, f · t, h · s, w · s, out]`, less the leading `t - 1` frames on
    /// the first chunk.
    func callAsFunction(_ x: MLXArray, firstChunk: Bool) -> MLXArray {
        let (t, s) = (temporalFactor, spatialFactor)
        let (batch, frames, height, width) = (x.dim(0), x.dim(1), x.dim(2), x.dim(3))
        let stretched = repeated(x, count: repeats, axis: -1)
            .reshaped([batch, frames, height, width, outputChannels, t, s, s])
            .transposed(0, 1, 5, 2, 6, 3, 7, 4)
            .reshaped([batch, frames * t, height * s, width * s, outputChannels])
        return firstChunk ? stretched[0..., (t - 1)...] : stretched
    }
}

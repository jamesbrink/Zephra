import Foundation
import MLX
import MLXNN

/// The upsampler's one resampling step: a two-dimensional convolution to four times the
/// channels, run frame by frame, and those channels folded into height and width.
///
/// The reference wraps the convolution and the shuffle in a `Sequential`, so the checkpoint
/// names the kernel `upsampler.0.weight`; a dotted integer unflattens to a list in MLX, which
/// is why `LTX2LatentUpsampler` holds the sequence as a one-element `[Conv2d]` and the shuffle,
/// which has no weights, lives here as a function of that list. Frames are folded into the
/// batch for the convolution, exactly as the reference permutes and flattens them, so each
/// frame is resampled on its own and the frame count is untouched.
///
/// The fold's channel order is the reference's `PixelShuffleND(2)`: for one output channel,
/// the four input channels run over the height offset first, then the width offset, and a
/// shuffle in the other order doubles the size to a tiled mess.
enum LTX2SpatialPixelShuffle {
    /// `[b, f, h, w, c]` to `[b, f, 2h, 2w, c]` through the sequence's convolution.
    static func doubled(_ x: MLXArray, through sequence: [Conv2d]) -> MLXArray {
        precondition(sequence.count == 1, "the upsampler is one convolution then the shuffle")
        let (batch, frames, height, width, channels) = (x.dim(0), x.dim(1), x.dim(2), x.dim(3), x.dim(4))
        let perFrame = sequence[0](x.reshaped([batch * frames, height, width, channels]))
        return shuffled(perFrame).reshaped([batch, frames, height * 2, width * 2, -1])
    }

    /// `[n, h, w, c·2·2]` to `[n, 2h, 2w, c]`, channels-last throughout.
    static func shuffled(_ x: MLXArray) -> MLXArray {
        let (count, height, width) = (x.dim(0), x.dim(1), x.dim(2))
        let channels = x.dim(3) / 4
        return x.reshaped([count, height, width, channels, 2, 2])
            .transposed(0, 1, 4, 2, 5, 3)
            .reshaped([count, height * 2, width * 2, channels])
    }
}

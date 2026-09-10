import Foundation
import MLX

/// The pixel shuffle at both doors of the autoencoder: a `patch x patch` square of each
/// colour folded into the channel axis on the way in and unfolded on the way out.
///
/// The channel order is the reference's and is not the obvious one: for one colour the
/// `patch²` channels run over the column offset first, then the row offset. Folding the
/// other way round makes an image of the right size with every 2 x 2 block transposed.
/// Channels-last throughout, `[batch, frames, height, width, channels]`.
enum WanPatchify {
    /// `[b, f, h · p, w · p, c]` to `[b, f, h, w, c · p · p]`.
    static func patchified(_ x: MLXArray, patch p: Int) -> MLXArray {
        guard p > 1 else { return x }
        let (batch, frames, channels) = (x.dim(0), x.dim(1), x.dim(4))
        let (height, width) = (x.dim(2) / p, x.dim(3) / p)
        return x.reshaped([batch, frames, height, p, width, p, channels])
            .transposed(0, 1, 2, 4, 6, 5, 3)
            .reshaped([batch, frames, height, width, channels * p * p])
    }

    /// `[b, f, h, w, c · p · p]` to `[b, f, h · p, w · p, c]`, the exact inverse.
    static func unpatchified(_ x: MLXArray, patch p: Int) -> MLXArray {
        guard p > 1 else { return x }
        let (batch, frames, height, width) = (x.dim(0), x.dim(1), x.dim(2), x.dim(3))
        let channels = x.dim(4) / (p * p)
        return x.reshaped([batch, frames, height, width, channels, p, p])
            .transposed(0, 1, 2, 6, 3, 5, 4)
            .reshaped([batch, frames, height * p, width * p, channels])
    }
}

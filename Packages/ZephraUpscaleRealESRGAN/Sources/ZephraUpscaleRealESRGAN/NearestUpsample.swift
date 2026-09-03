import Foundation
import MLX

/// Pixel replication at an integer factor: every pixel becomes a `factor` by `factor` block.
///
/// This is the network's residual branch. The reference reaches it through
/// `F.interpolate(x, scale_factor=self.upscale, mode='nearest')`, which at an integer factor is
/// exactly replication — no sampling grid, no rounding rule to get wrong. Writing it as
/// replication rather than as a general resampler is what makes that exactness testable, and
/// the residual being nearest rather than bilinear is load-bearing: the network learned to
/// predict the difference from this particular base.
public enum NearestUpsample {
    /// Replicates each pixel of `x`, NHWC, into a `factor` by `factor` block.
    public static func apply(_ x: MLXArray, factor: Int) -> MLXArray {
        let (batch, height, width, channels) = (x.dim(0), x.dim(1), x.dim(2), x.dim(3))
        let expanded = x.reshaped([batch, height, 1, width, 1, channels])
        return MLX.broadcast(expanded, to: [batch, height, factor, width, factor, channels])
            .reshaped([batch, height * factor, width * factor, channels])
    }
}

import Foundation
import MLX

/// The exact 2x2 box mean that turns a 4x result into a 2x one.
///
/// There is no 2x checkpoint in this family worth carrying beside the 4x one, so 2x is the same
/// pass followed by this. A box mean over a whole number of pixels is the one downsample with
/// no filter design in it: each output pixel is the arithmetic mean of the four that map onto
/// it, so it needs no window, no kernel, and no edge rule, and it is exact rather than a
/// resampler's approximation.
///
/// The cost of that honesty is that 2x is not cheaper than 4x — it is 4x plus this. A Lanczos
/// halving would look slightly crisper and is in `ROADMAP.md`; it would also be a filter to
/// defend, which the box mean is not.
public enum BoxDownsample {
    /// Halves each edge of `pixels`, NHWC, by averaging every 2x2 block.
    ///
    /// Both spatial edges must be even, which they are: this only ever sees the output of a 4x
    /// pass, whose edges are four times an integer.
    public static func half(_ pixels: MLXArray) -> MLXArray {
        let (batch, height, width, channels) =
            (pixels.dim(0), pixels.dim(1), pixels.dim(2), pixels.dim(3))
        precondition(
            height % 2 == 0 && width % 2 == 0, "a box mean halves whole pixels, not half ones")
        return pixels
            .reshaped([batch, height / 2, 2, width / 2, 2, channels])
            .mean(axes: [2, 4])
    }
}

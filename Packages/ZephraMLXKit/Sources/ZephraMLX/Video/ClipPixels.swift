import Foundation
import MLX

/// Turning a video decoder's output into bytes: a whole clip as RGBA8, and its first frame as
/// PNG. The same for every family that makes clips; each kit wraps the bytes in its own video
/// type.
///
/// A channel value lands on the **nearest** byte, clipped to 0...255, the same rounding
/// `PixelBuffer` gives a picture and `diffusers` gives a frame (`(x * 255).round()` in
/// `numpy_to_pil`); LTX's own video export truncates instead, which pulls every channel down
/// by up to one step, and is not followed. The clip is rounded as one tensor rather than frame
/// by frame because it is one tensor already, and `PixelBuffer.rgba8` takes only the first
/// image of a batch.
public enum ClipPixels {
    /// The clip `video`, `[1, frames, height, width, 3]` in the range -1 to 1, as opaque RGBA8:
    /// `frames * height * width * 4` bytes, frame-major.
    public static func rgba8(_ video: MLXArray) -> Data {
        let frames = video[0]
        let (count, height, width) = (frames.dim(0), frames.dim(1), frames.dim(2))
        let scaled = MLX.clip(
            MLX.round((frames.asType(.float32) + 1) * 127.5),
            min: MLXArray(Float(0)), max: MLXArray(Float(255)))
        let opaque = MLX.concatenated(
            [scaled, MLXArray.full([count, height, width, 1], values: MLXArray(Float(255)))],
            axis: -1)
        MLX.eval(opaque)
        return opaque.asType(.uint8).asData().data
    }

    /// The first frame of `video`, `[1, frames, height, width, 3]`, as PNG: what the library
    /// indexes and the grid draws for a clip.
    public static func posterPNG(_ video: MLXArray) throws -> Data {
        try PixelBuffer.png(from: video[0..., 0].asType(.float32))
    }
}

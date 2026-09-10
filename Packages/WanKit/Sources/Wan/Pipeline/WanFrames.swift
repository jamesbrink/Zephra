import Foundation
import MLX
import ZephraMLX

/// The decoder's output as this kit's video type: the bytes are `ClipPixels`', shared with
/// every family that makes clips.
public enum WanFrames {
    /// The clip `video`, `[1, frames, height, width, 3]` in the range -1 to 1 as the decoder
    /// hands it back, as opaque RGBA8.
    public static func video(_ video: MLXArray, frameRate: Double) -> WanVideo {
        WanVideo(
            width: video.dim(3), height: video.dim(2), frameCount: video.dim(1), frameRate: frameRate,
            pixels: ClipPixels.rgba8(video))
    }

    /// The first frame of `video`, `[1, frames, height, width, 3]`, as PNG: what the library
    /// indexes and the grid draws for a clip.
    public static func posterPNG(_ video: MLXArray) throws -> Data {
        try ClipPixels.posterPNG(video)
    }
}

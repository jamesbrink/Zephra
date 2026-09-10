import CoreGraphics
import Foundation
import MLX
import ZephraMLX

/// The picture a clip is held from, turned into the video encoder's input.
///
/// The drawing — scaled to cover the clip and cropped to the middle — is `CoveringPicture`'s,
/// shared with every family that holds a first frame; what is this family's is the layout the
/// encoder wants. The other direction, the decoder's output as bytes, is `LTX2Frames`.
public enum LTX2FirstFramePixels {
    /// Draws `image` at `width` by `height` and returns it the way the encoder wants it.
    ///
    /// - Returns: `[1, 3, 1, height, width]` in the range -1 to 1 — channels first and one
    ///   frame, which is a clip of a single picture and encodes to a single latent frame.
    public static func pixels(from image: CGImage, width: Int, height: Int) throws -> MLXArray {
        guard let rgb = CoveringPicture.pixels(from: image, width: width, height: height) else {
            throw LTX2PipelineError.unreadableFirstFrame
        }
        return rgb.transposed(0, 3, 1, 2).expandedDimensions(axis: 2)
    }

    /// Where the picture is drawn; `CoveringPicture`'s rule, kept here for the tests that pin it.
    static func fill(_ image: CGImage, width: Int, height: Int) -> CGRect {
        CoveringPicture.fill(image, width: width, height: height)
    }
}

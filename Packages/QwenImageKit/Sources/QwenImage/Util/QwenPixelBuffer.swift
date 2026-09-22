import CoreGraphics
import Foundation
import MLX

/// A reference picture turned into the encoder's input.
///
/// It takes a `CGImage`; reading one off disk is the backend's job, not the kit's, so nothing
/// here opens a file. The other direction — the decoder's output as PNG or as a preview
/// frame's bytes — is `PixelBuffer` in `ZephraMLX`, the same for every family.
public enum QwenPixelBuffer {
    /// Draws `image` at `width` by `height` and returns it the way the encoder wants it.
    ///
    /// - Returns: `[1, height, width, 3]` in the range -1 to 1, which is `png(from:)`'s input
    ///   scale and shape, so a picture that goes through `encode` and back out of `decode`
    ///   arrives in the units it left in.
    ///
    /// The reference does not care how the picture is scaled to the generation's size, and this
    /// takes CoreGraphics' default resampling, which fills the frame — a reference of a
    /// different aspect ratio is stretched rather than cropped or letterboxed. Cropping is a
    /// decision for whoever chose the picture, not for the encoder.
    public static func pixels(from image: CGImage, width: Int, height: Int) throws -> MLXArray {
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { throw QwenImagePipelineError.encodingFailed }
            // Cleared to **white**, not to the zeroes a fresh bitmap holds: a reference
            // picture may carry transparency now, and a matte decides what its clear pixels
            // encode as. Black was what an uncleared buffer happened to give; white is what
            // a person expects and what the 2.1 pipeline prescribes for its own references.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = context.data else { throw QwenImagePipelineError.encodingFailed }

        let count = width * height * 4
        let buffer = UnsafeBufferPointer(
            start: bytes.assumingMemoryBound(to: UInt8.self), count: count)
        let rgba = MLXArray(Array(buffer)).reshaped([1, height, width, 4])
        let rgb = rgba[0..., 0..., 0..., 0 ..< 3].asType(.float32)
        return rgb / MLXArray(Float(127.5)) - MLXArray(Float(1))
    }
}

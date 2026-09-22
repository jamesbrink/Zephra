import CoreGraphics
import Foundation
import ImageIO
import MLX

/// A reference picture's bytes turned into the one resized copy both halves of the model read.
///
/// The reference pipeline does this in `__call__`, before either copy is made: every condition
/// image is converted to RGBA, its own aspect is put through
/// `calculate_dimensions(output_resolution², ratio)` — a multiple of 32 — and it is resized
/// **once** to that. `_get_qwen_prompt_embeds` then flattens that copy over white for the
/// vision tower, while the autoencoder keeps all four channels. Doing the resize here, at the
/// one door bytes come in through, is what keeps those two copies the same picture.
///
/// The size matters twice over. The tower's own `smart_resize` is required to be a no-op —
/// `Qwen3VLImagePreprocessing.patches` throws rather than resampling a second time — and the
/// autoencoder needs both edges on its sixteen-pixel grid. A multiple of 32 satisfies both.
///
/// **Two departures from the reference's resampler, both stated in `PROVENANCE.md`.**
/// The reference resizes with PIL's lanczos; this draws through Core Graphics at
/// `.high` interpolation, which is a different kernel and puts a reference-conditioned picture
/// a resample away from the reference's. And Core Graphics has no straight-alpha context at
/// all, so the draw is premultiplied and un-premultiplied afterwards: colour under a fully
/// transparent pixel is lost, which is the colour the autoencoder does not carry either.
public enum QwenImage21ReferencePicture {
    /// Decodes and fits one picture to `[height, width, 4]` over 0 to 255, straight alpha.
    ///
    /// - Parameters:
    ///   - data: The encoded picture, anything ImageIO reads.
    ///   - targetArea: The area the fit aims for, `output_resolution²`.
    public static func fitted(
        _ data: Data,
        targetArea: Int = QwenImage21ImageFitting.outputResolution
            * QwenImage21ImageFitting.outputResolution
    ) throws -> MLXArray {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
            image.width > 0, image.height > 0
        else { throw QwenImage21PipelineError.unreadableReference }

        let target = QwenImage21ImageFitting.dimensions(
            targetArea: targetArea,
            ratio: QwenImage21ImageFitting.ratio(width: image.width, height: image.height))
        return try drawn(image, width: target.width, height: target.height)
    }

    /// `image` resampled into a `width` by `height` RGBA array over 0 to 255, straight alpha.
    static func drawn(_ image: CGImage, width: Int, height: Int) throws -> MLXArray {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            // The whole picture into the whole bitmap. The fit keeps the aspect to within one
            // 32-pixel step, so there is nothing to crop and nothing to letterbox: a matte
            // colour here would be a matte the reference never applies.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { throw QwenImage21PipelineError.unreadableReference }

        let premultiplied = MLXArray(bytes, [height, width, 4]).asType(.float32)
        let alpha = premultiplied[.ellipsis, 3..<4]
        // `maximum` rather than a `where`: a fully transparent pixel divides by one and keeps
        // the zero it already holds, which is the colour a premultiplied buffer no longer has.
        let colour = MLX.minimum(
            MLX.round(premultiplied[.ellipsis, 0..<3] * 255 / MLX.maximum(alpha, 1)), 255)
        return MLX.concatenated([colour, alpha], axis: -1)
    }
}

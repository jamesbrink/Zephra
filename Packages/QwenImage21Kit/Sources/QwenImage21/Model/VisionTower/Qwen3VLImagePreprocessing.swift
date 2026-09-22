import Foundation
import MLX

/// How a reference picture reaches the tower: alpha flattened over white, normalised to
/// [-1, 1], and cut into block-major patch vectors of 1536.
///
/// Three rules from the pipeline, in order.
///
/// **The alpha goes over white, and only for this copy.** 2.1's autoencoder is four-channel and
/// the VAE reads all four, but the tower was trained on three, and the reference composites the
/// picture onto a white background rather than dropping the channel or premultiplying by black.
/// A picture with transparency handed to the tower unflattened reads as though the transparent
/// parts were dark.
///
/// **`smart_resize` is a no-op and this port requires it to be.** The pipeline has already
/// fitted every reference to `calculate_dimensions(1024², ratio)`, a multiple of 32, before
/// either copy is made, and 32 is exactly `patch_size * merge_size`; the tower's own
/// `smart_resize` then finds the picture already conformant and returns it. So `fitted(_:_:)`
/// is here as the arithmetic, checked against the reference for six shapes, and
/// `patches(of:)` **throws** rather than resampling a picture that does not match it. The
/// alternative is a second bicubic resampler in this kit whose only job is to disagree with
/// the pipeline's lanczos one.
///
/// **The patchify is block-major**, so the four patches a merge combines are adjacent, and a
/// still picture is repeated along the frame axis to fill `temporal_patch_size`, which is what
/// makes a patch vector `3 * 2 * 16 * 16`.
public enum Qwen3VLImagePreprocessing {
    /// The size `smart_resize` brings a `height` by `width` picture to.
    ///
    /// - Parameters:
    ///   - factor: `patch_size * merge_size`, 32 here.
    ///   - minPixels: `size.shortest_edge`, 65,536 — 256 squared.
    ///   - maxPixels: `size.longest_edge`, 16,777,216 — 4096 squared.
    ///
    /// The rounding is Python's `round`, which breaks a tie to even; Swift's
    /// `.toNearestOrEven` is the same rule and a tie is reachable at this factor.
    public static func fitted(
        height: Int, width: Int, factor: Int, minPixels: Int, maxPixels: Int
    ) throws -> (height: Int, width: Int) {
        let long = Double(max(height, width))
        let short = Double(min(height, width))
        guard short > 0, long / short <= 200 else {
            throw Qwen3VLEncodingError.aspectRatioTooExtreme(height: height, width: width)
        }
        var bars = (
            height: rounded(Double(height) / Double(factor)) * factor,
            width: rounded(Double(width) / Double(factor)) * factor
        )
        let area = Double(height) * Double(width)
        if bars.height * bars.width > maxPixels {
            let beta = (area / Double(maxPixels)).squareRoot()
            bars.height = max(factor, Int((Double(height) / beta / Double(factor)).rounded(.down)) * factor)
            bars.width = max(factor, Int((Double(width) / beta / Double(factor)).rounded(.down)) * factor)
        } else if bars.height * bars.width < minPixels {
            let beta = (Double(minPixels) / area).squareRoot()
            bars.height = Int((Double(height) * beta / Double(factor)).rounded(.up)) * factor
            bars.width = Int((Double(width) * beta / Double(factor)).rounded(.up)) * factor
        }
        return bars
    }

    /// An RGBA picture, `[height, width, 4]` over 0 to 255, flattened onto white as
    /// `[height, width, 3]`.
    ///
    /// The reference does this with PIL's `paste` and an alpha mask, which is integer
    /// arithmetic; the rounded float blend here agrees with it byte for byte on the fixture,
    /// and both are stated in `PROVENANCE.md`.
    public static func compositedOverWhite(_ rgba: MLXArray) -> MLXArray {
        let alpha = rgba[.ellipsis, 3..<4] / 255
        return MLX.round(255 * (1 - alpha) + rgba[.ellipsis, 0..<3] * alpha)
    }

    /// The three-channel copy the tower reads, whatever it was handed.
    ///
    /// `[height, width, 4]` is flattened over white; `[height, width, 3]` passes through. This
    /// is the one door, so a caller cannot reach the tower with an unflattened picture: the
    /// autoencoder's copy keeps all four channels and is taken elsewhere, from the same resize.
    public static func towerInput(_ picture: MLXArray) -> MLXArray {
        picture.dim(-1) == 4 ? compositedOverWhite(picture) : picture
    }

    private static func rounded(_ value: Double) -> Int { Int(value.rounded(.toNearestOrEven)) }
}

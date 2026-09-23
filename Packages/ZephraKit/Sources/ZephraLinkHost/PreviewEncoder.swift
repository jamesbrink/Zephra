import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZephraCore
import ZephraLinkProtocol

/// A frame of the run in flight, encoded small enough to send several times a second.
///
/// JPEG at 0.6 rather than the engine's raw RGBA8: a 256-pixel preview is a quarter of a
/// megabyte of pixels and a few kilobytes encoded, and these cross a link that may be a relay on
/// the far side of the world. Quality 0.6 because nobody judges a picture by its preview — the
/// frame is there to say the run is moving and roughly what it is drawing.
///
/// Everything here is `nonisolated` and static, and every caller runs it in a detached task:
/// encoding on the main actor would put an Image I/O pass between the engine and the interface
/// ten times a second.
public enum PreviewEncoder {
    /// How compressed a frame is.
    public static let quality = 0.6

    /// The frame as JPEG, or nil when the buffer is not the length its size claims or Image I/O
    /// will not take it.
    public nonisolated static func encode(_ preview: GenerationPreview) -> Data? {
        guard preview.isWellFormed else { return nil }
        // A frame from a model that makes no transparency takes exactly the path it always
        // did, bitmap for bitmap: the composite below is a second pass over the pixels ten
        // times a second, and it is owed to the one model that needs it.
        let transparent = preview.hasTransparency
        guard let frame = makeImage(preview, transparent: transparent),
            let image = transparent ? CheckerboardComposite.over(frame) : frame
        else { return nil }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            bytes, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return bytes as Data
    }

    /// The frame as the message the phone reads, or nil when it could not be encoded.
    public nonisolated static func frame(
        _ preview: GenerationPreview, step: Int, steps: Int
    ) -> PreviewFrameDTO? {
        encode(preview).map {
            PreviewFrameDTO(
                jpeg: $0, width: preview.width, height: preview.height, step: step, steps: steps)
        }
    }

    /// The pixels as a `CGImage`.
    ///
    /// A frame with nothing transparent in it is `noneSkipLast`, as every frame was before
    /// there was any alpha to read: the fourth byte is 255 throughout and skipping it spares
    /// Core Graphics a channel it would only multiply by one. A frame that does carry alpha is
    /// `CGImageAlphaInfo.last` — the straight alpha `PixelBuffer` packs, not premultiplied —
    /// and the caller lays it over `Checkerboard` before the encode, because JPEG has no alpha
    /// channel and flattening against whatever Image I/O picks would show a person black where
    /// their picture is clear.
    private nonisolated static func makeImage(
        _ preview: GenerationPreview, transparent: Bool
    ) -> CGImage? {
        guard let provider = CGDataProvider(data: preview.pixels as CFData) else { return nil }
        return CGImage(
            width: preview.width,
            height: preview.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: preview.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: transparent
                    ? CGImageAlphaInfo.last.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
    }
}

import CoreGraphics
import Foundation
import ZephraCore

/// A transparent picture laid over `Checkerboard`, for the two places that must send JPEG.
///
/// Both of them are link payloads: a grid thumbnail, which is JPEG because that is what
/// `BlobStart` names and what every other picture on the wire is, and a preview frame, which
/// is JPEG because a PNG ten times a second over a relay is a real cost. Neither format can
/// carry alpha, so rather than let Image I/O flatten a transparent picture against whatever it
/// picks, each composites it over the same squares the Mac and the phone draw live. A phone
/// then reads a transparent picture as transparent with no protocol change and no mime
/// switching.
///
/// An opaque picture is handed straight back, so every model that came before transparency
/// pays nothing at all for this.
public enum CheckerboardComposite {
    /// `image` over the checkerboard when it carries alpha, and `image` itself when it does
    /// not. Nil only when Core Graphics refuses the bitmap.
    public static func flattened(_ image: CGImage) -> CGImage? {
        guard carriesAlpha(image) else { return image }
        return over(image)
    }

    /// `image` drawn over the checkerboard at its own pixel size, whatever its alpha.
    public static func over(_ image: CGImage) -> CGImage? {
        let (width, height) = (image.width, image.height)
        guard width > 0, height > 0,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        draw(into: context, width: width, height: height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Whether the bitmap has an alpha channel at all. A fully opaque RGBA picture composites
    /// to itself, so this asks the cheap question rather than reading every fourth byte.
    static func carriesAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: true
        case .none, .noneSkipFirst, .noneSkipLast: false
        @unknown default: false
        }
    }

    /// Fills `context` with the checkerboard. `Checkerboard`'s parity is in pixels from the top
    /// left and a bitmap context's origin is at the bottom left, so each row is drawn at the
    /// height less its own offset: the square in a picture's top left corner is the light one,
    /// on screen and in every composite.
    private static func draw(into context: CGContext, width: Int, height: Int) {
        let cell = Checkerboard.cell
        context.setFillColor(gray: CGFloat(Checkerboard.light) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: CGFloat(Checkerboard.dark) / 255, alpha: 1)
        var top = 0
        while top < height {
            var left = 0
            while left < width {
                if !Checkerboard.isLight(x: left, y: top) {
                    context.fill(
                        CGRect(
                            x: left, y: height - top - cell, width: cell, height: cell))
                }
                left += cell
            }
            top += cell
        }
    }
}

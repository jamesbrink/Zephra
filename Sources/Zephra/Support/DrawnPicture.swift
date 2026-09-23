import AppKit
import ZephraStyle

/// Decoded pixels and the one thing a view has to know about them before it draws: whether
/// they carry transparency, and so whether the ground under them is the checkerboard.
///
/// The answer is taken at the decode, off the main actor, where the `CGImage` is already in
/// hand and `alphaInfo` is a property read. A view asking for itself would either decode in
/// `body` or reach back to the file, and neither is allowed here.
///
/// A class rather than a struct because `NSCache` holds objects, and because both caches hand
/// the same object to every view that asks for the same picture.
final class DrawnPicture {
    /// The pixels, wrapped for SwiftUI.
    let image: NSImage
    /// Whether those pixels carry an alpha channel.
    let hasAlpha: Bool

    /// Wraps a decoded picture and what its bitmap says about its alpha.
    init(_ image: NSImage, hasAlpha: Bool) {
        self.image = image
        self.hasAlpha = hasAlpha
    }

    /// The same, from the `CGImage` the decode produced: `points` is the size to give the
    /// `NSImage`, which is half the pixels for a 2x thumbnail and `.zero` for a picture drawn
    /// at whatever size the view has.
    convenience init(_ decoded: CGImage, points: NSSize = .zero) {
        self.init(
            NSImage(cgImage: decoded, size: points), hasAlpha: decoded.hasTransparency)
    }
}

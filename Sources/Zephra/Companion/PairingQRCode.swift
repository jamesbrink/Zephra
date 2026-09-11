import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// The pairing link as a square somebody photographs across a desk.
///
/// Core Image draws a code one module per pixel, which at a version 11 grid is about sixty
/// pixels square; drawn at two hundred and forty points that is a blur. So it is scaled by whole
/// numbers with no interpolation, which keeps every module a hard square — what a camera wants,
/// and what makes the code readable at an angle and in poor light.
///
/// Medium error correction: the payload is measured at around five hundred characters and the
/// budget is six hundred, so the correction level is what is left to spend, and `M` is what a
/// screen wants — a code on glass is not a label that gets scuffed.
enum PairingQRCode {
    /// How much correction the code carries, as Core Image spells it.
    static let correction = "M"

    /// The code for one link, at roughly `points` on a side, or nil when Core Image will not
    /// draw it.
    static func image(for link: String, points: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.utf8)
        filter.correctionLevel = correction
        guard let drawn = filter.outputImage else { return nil }
        let scale = max(1, (points / max(drawn.extent.width, 1)).rounded(.down))
        let scaled = drawn.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: CGSize(width: points, height: points))
    }
}

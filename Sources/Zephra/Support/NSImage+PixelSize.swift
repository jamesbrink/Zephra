import AppKit

extension NSImage {
    /// The picture's size in pixels, whatever its points say: a PNG with a resolution chunk
    /// other than 72 dpi has a point size that is not its pixel size, and zoom is about pixels.
    /// The largest bitmap representation's, else the point size where there is no bitmap.
    var pixelSize: CGSize {
        let widest = representations.max { $0.pixelsWide < $1.pixelsWide }
        if let widest, widest.pixelsWide > 0, widest.pixelsHigh > 0 {
            return CGSize(width: widest.pixelsWide, height: widest.pixelsHigh)
        }
        return size
    }
}

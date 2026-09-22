import Foundation
import ZephraCore

/// The pixel dimensions a PNG declares, read out of its own header.
///
/// The one honest answer to "how big did that come back": an upscaler trims its input to a
/// multiple of its stride, so the result's edges are not always the parent's times the factor.
/// The `IHDR` chunk is the first one in every PNG and its body starts with the two numbers, so
/// this is a read of a few dozen bytes rather than a decode of the picture.
public enum PNGImageSize {
    /// The size `data` declares, or nil when it is not a PNG, stops before its header, or
    /// claims an edge of zero.
    ///
    /// `PNGHeader`'s walk, which reads the same `IHDR` for its size, its colour type and the
    /// text beside it: one reader of the format, so a file cannot be two sizes.
    public static func read(from data: Data) -> ImageSize? {
        try? PNGHeader.read(from: data).size
    }
}

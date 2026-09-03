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
    public static func read(from data: Data) -> ImageSize? {
        let bytes = Array(data)
        guard let header = try? PNGTextChunks.spans(in: bytes).first(where: { $0.type == "IHDR" }),
              header.body.count >= 8
        else { return nil }
        let width = Int(PNGTextChunks.be32(bytes, at: header.body.lowerBound))
        let height = Int(PNGTextChunks.be32(bytes, at: header.body.lowerBound + 4))
        guard width > 0, height > 0 else { return nil }
        return ImageSize(width: width, height: height)
    }
}

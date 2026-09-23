import Foundation

/// Reading a PNG's text without reading the picture.
///
/// Text chunks are written ahead of the first `IDAT`, so the whole of Zephra's metadata sits in
/// the first few kilobytes of a file whose pixels are megabytes. A library scan of a thousand
/// images reads a thousand headers rather than a gigabyte of compressed image data, which is
/// the difference between a scan that is instant and one that is not.
extension PNGTextChunks {
    /// Every `tEXt` and `iTXt` chunk before the first `IDAT` of the file at `url`.
    ///
    /// `PNGHeader`'s walk, which seeks past a chunk too large to want: a reference picture's
    /// megabyte is stepped over rather than read, and no size of prefix decides the answer. The
    /// same answer as `read(from:)` for anything Zephra wrote, at a fraction of the reading —
    /// text after the image data is not seen, and nothing here writes any.
    public static func read(fromHeaderOf url: URL) throws -> [String: String] {
        try PNGHeader.read(fromHeaderOf: url).text
    }
}

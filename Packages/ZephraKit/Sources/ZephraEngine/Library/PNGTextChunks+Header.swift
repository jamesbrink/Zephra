import Foundation

/// Reading a PNG's text without reading the picture.
///
/// Text chunks are written ahead of the first `IDAT`, so the whole of Zephra's metadata sits in
/// the first few kilobytes of a file whose pixels are megabytes. A library scan of a thousand
/// images reads a thousand headers rather than a gigabyte of compressed image data, which is
/// the difference between a scan that is instant and one that is not.
extension PNGTextChunks {
    /// How far into the file to read before giving up on finding `IDAT` in a prefix.
    ///
    /// Three sizes rather than one: 64 KiB covers every file Zephra writes, and the larger two
    /// exist for a foreign PNG carrying an ICC profile or an EXIF blob ahead of its image data.
    static let headerReadSizes = [64 << 10, 256 << 10, 1 << 20]

    /// Every `tEXt` and `iTXt` chunk before the first `IDAT` of the file at `url`.
    ///
    /// The same answer as `read(from:)` for anything Zephra wrote, at a fraction of the reading:
    /// text after the image data is not seen, and nothing here writes any. A file whose image
    /// data starts past a megabyte falls back to reading the whole thing, so the answer is
    /// never wrong, only slower.
    public static func read(fromHeaderOf url: URL) throws -> [String: String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        for size in headerReadSizes {
            try handle.seek(toOffset: 0)
            let prefix = try handle.read(upToCount: size) ?? Data()
            if let found = try textBeforeImageData(in: Array(prefix)) { return found }
            // A short read is the whole file: growing the window cannot find more.
            if prefix.count < size { break }
        }
        return try read(from: try Data(contentsOf: url))
    }

    /// The text chunks up to the first `IDAT`, or nil when `IDAT` is not in these bytes yet.
    ///
    /// Deliberately lenient about the end: a prefix stops in the middle of a chunk, which is
    /// not a malformed file. A file that really is truncated reads as nil here and then throws
    /// on the full read, which is where the strict walk lives.
    static func textBeforeImageData(in bytes: [UInt8]) throws -> [String: String]? {
        guard bytes.count >= 8, Array(bytes[0..<8]) == signature else { throw Failure.notAPNG }
        var offset = 8
        var found: [String: String] = [:]
        while offset + 8 <= bytes.count {
            let length = Int(be32(bytes, at: offset))
            let bodyStart = offset + 8
            let type = String(decoding: bytes[(offset + 4)..<bodyStart], as: UTF8.self)
            if type == "IDAT" { return found }
            guard bodyStart + length + 4 <= bytes.count else { return nil }
            let span = Span(type: type, start: offset, body: bodyStart..<(bodyStart + length))
            if let entry = decode(span, in: bytes) { found[entry.keyword] = entry.text }
            if type == "IEND" { return found }
            offset = bodyStart + length + 4
        }
        return nil
    }
}

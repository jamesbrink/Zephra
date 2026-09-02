import Foundation

/// PNG text chunks (`tEXt` and `iTXt`), read and written without re-encoding the pixels.
///
/// Insertion splices new chunks in ahead of the first `IDAT` and leaves every existing byte
/// exactly where it was, so the compressed image data of an annotated file is byte-identical to
/// the original's: a fixed seed still produces the same picture on disk, metadata aside.
public enum PNGTextChunks {
    /// One text chunk: the keyword it is filed under and the text stored there.
    public typealias Entry = (keyword: String, text: String)

    /// What can be wrong with the bytes handed in.
    public enum Failure: Error, Equatable {
        /// The data does not begin with the eight-byte PNG signature.
        case notAPNG
        /// A chunk header or body runs off the end of the data.
        case truncated
        /// There is no `IDAT` chunk to splice ahead of.
        case noImageData
        /// A keyword PNG will not accept: empty, longer than 79 bytes, not printable ASCII, or
        /// padded with a space at either end.
        case invalidKeyword(String)
    }

    /// The eight bytes every PNG starts with.
    static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Every `tEXt` and `iTXt` chunk in the file, by keyword.
    ///
    /// A keyword that appears more than once reads as its last occurrence, which is the one the
    /// most recent insertion wrote. Compressed text — `zTXt`, or an `iTXt` flagged as
    /// compressed — is skipped rather than inflated: Zephra never writes either.
    public static func read(from data: Data) throws -> [String: String] {
        let bytes = Array(data)
        var found: [String: String] = [:]
        for span in try spans(in: bytes) {
            guard let entry = decode(span, in: bytes) else { continue }
            found[entry.keyword] = entry.text
        }
        return found
    }

    /// A copy of `data` with `entries` spliced in just before the first `IDAT`, in the order
    /// given: a `tEXt` where the text fits Latin-1, an `iTXt` where it needs UTF-8.
    public static func inserting(_ entries: [Entry], into data: Data) throws -> Data {
        let bytes = Array(data)
        guard let image = try spans(in: bytes).first(where: { $0.type == "IDAT" }) else {
            throw Failure.noImageData
        }
        var inserted = Data()
        for entry in entries { inserted.append(try chunk(for: entry)) }
        var result = Data(capacity: bytes.count + inserted.count)
        result.append(contentsOf: bytes[..<image.start])
        result.append(inserted)
        result.append(contentsOf: bytes[image.start...])
        return result
    }

    /// Where one chunk sits in the file.
    struct Span {
        /// The four-character chunk type, `IHDR` through `IEND`.
        let type: String
        /// The offset of the chunk's length field, which is where the chunk begins.
        let start: Int
        /// The bytes between the type and the CRC.
        let body: Range<Int>
    }

    /// The chunk list, from the signature to `IEND`. Throws rather than guessing when the file
    /// is not a PNG or stops in the middle of a chunk.
    static func spans(in bytes: [UInt8]) throws -> [Span] {
        guard bytes.count >= 8, Array(bytes[0..<8]) == signature else { throw Failure.notAPNG }
        var offset = 8
        var found: [Span] = []
        while offset + 8 <= bytes.count {
            let length = Int(be32(bytes, at: offset))
            let bodyStart = offset + 8
            guard bodyStart + length + 4 <= bytes.count else { throw Failure.truncated }
            let type = String(decoding: bytes[(offset + 4)..<bodyStart], as: UTF8.self)
            found.append(Span(type: type, start: offset, body: bodyStart..<(bodyStart + length)))
            if type == "IEND" { break }
            offset = bodyStart + length + 4
        }
        return found
    }

    /// Reads a big-endian 32-bit integer, which is the only integer encoding PNG uses.
    static func be32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }
}

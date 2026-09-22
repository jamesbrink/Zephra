import Foundation
import ZephraCore

/// Everything a PNG's header says, read in one seeking walk: its text, its size, and whether
/// its pixels carry alpha.
///
/// Three answers from one pass, because every caller that wanted one of them wanted the others
/// too: a library scan reads the record, the annotation and now the transparency of every file
/// it re-reads, and asking three times would be three walks of the same bytes.
///
/// The walk **seeks** rather than reading a prefix. A picture carrying a 1024-pixel reference
/// has a text chunk of about 1.4 MB, which defeated the old prefix-growing read at all three of
/// its sizes and sent every edit in the library through `Data(contentsOf:)` — the whole file,
/// pixels included, on every scan that re-read it. Here a chunk larger than `bodyReadLimit` is
/// stepped over without being read at all, so a folder of edits costs a few small reads a file
/// whatever its references weigh.
public struct PNGHeader: Hashable, Sendable {
    /// The pixel dimensions `IHDR` declares, or nil when there is no usable `IHDR`.
    public let size: ImageSize?
    /// Whether the picture can hold transparency: colour type 4 or 6, or a `tRNS` chunk, which
    /// is how a palette picture somebody imported carries it.
    public let hasAlpha: Bool
    /// Every `tEXt` and `iTXt` chunk before the first `IDAT`, by keyword.
    public let text: [String: String]

    /// The largest chunk body this reads rather than steps over. Every text chunk Zephra writes
    /// but a reference picture is far under it, and a reference is exactly what must not be
    /// read: the walk wants its keyword, not its megabyte.
    static let bodyReadLimit = 64 << 10

    /// The header of the file at `url`, without reading its pixels.
    ///
    /// Text after the first `IDAT` is not seen, and nothing here writes any. A file that stops
    /// in the middle of a chunk ahead of the image data throws, as the strict walk does.
    public static func read(fromHeaderOf url: URL) throws -> PNGHeader {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let signature = try handle.read(upToCount: 8),
              Array(signature) == PNGTextChunks.signature
        else { throw PNGTextChunks.Failure.notAPNG }

        var found = Builder()
        while true {
            guard let header = try handle.read(upToCount: 8), header.count == 8 else {
                throw PNGTextChunks.Failure.truncated
            }
            let bytes = Array(header)
            let length = Int(PNGTextChunks.be32(bytes, at: 0))
            let type = String(decoding: bytes[4..<8], as: UTF8.self)
            if type == "IDAT" { break }
            if length <= bodyReadLimit {
                guard let body = try handle.read(upToCount: length), body.count == length else {
                    throw PNGTextChunks.Failure.truncated
                }
                found.absorb(type: type, body: Array(body))
            } else {
                try handle.seek(toOffset: handle.offset() + UInt64(length))
            }
            if type == "IEND" { break }
            try handle.seek(toOffset: handle.offset() + 4)  // the chunk's CRC
        }
        return found.finished()
    }

    /// The same three answers from bytes already in memory, for a picture that has not reached
    /// the disk. Strict about truncation, like `PNGTextChunks.read(from:)`, which it walks with.
    public static func read(from data: Data) throws -> PNGHeader {
        let bytes = Array(data)
        var found = Builder()
        for span in try PNGTextChunks.spans(in: bytes) {
            if span.type == "IDAT" { break }
            found.absorb(type: span.type, body: Array(bytes[span.body]))
        }
        return found.finished()
    }

    /// What the walk has seen so far. One place decides what each chunk type means, so the two
    /// readers above cannot come to disagree about a colour type.
    private struct Builder {
        private var size: ImageSize?
        private var colourType: UInt8?
        private var sawTransparency = false
        private var text: [String: String] = [:]

        mutating func absorb(type: String, body: [UInt8]) {
            switch type {
            case "IHDR":
                // Width, height, bit depth, colour type: the first ten bytes of every PNG's
                // first chunk.
                guard body.count >= 10 else { return }
                let width = Int(PNGTextChunks.be32(body, at: 0))
                let height = Int(PNGTextChunks.be32(body, at: 4))
                if width > 0, height > 0 { size = ImageSize(width: width, height: height) }
                colourType = body[9]
            case "tRNS":
                sawTransparency = true
            default:
                let span = PNGTextChunks.Span(type: type, start: 0, body: 0..<body.count)
                guard let entry = PNGTextChunks.decode(span, in: body) else { return }
                text[entry.keyword] = entry.text
            }
        }

        func finished() -> PNGHeader {
            let alpha = colourType == 4 || colourType == 6 || sawTransparency
            return PNGHeader(size: size, hasAlpha: alpha, text: text)
        }
    }
}

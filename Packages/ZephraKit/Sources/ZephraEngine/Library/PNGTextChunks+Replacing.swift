import Foundation

/// Rewriting text that is already there.
///
/// `inserting(_:into:)` is for a file being written for the first time and only ever adds. A
/// favourite that is toggled twice would add twice, so annotation goes through this instead:
/// the chunks under the keywords being written are dropped, the new ones take their place, and
/// a file written a hundred times is the same size as one written once.
extension PNGTextChunks {
    /// A copy of `data` carrying `entries` and no other chunk under those keywords.
    ///
    /// Everything from the first `IDAT` to the end is copied byte for byte, so the pixels of an
    /// annotated file stay identical to the original's however often it is annotated. Chunks
    /// after the image data are left alone too, including text ones: this rewrites the header,
    /// which is the only place anything writes text.
    public static func replacing(_ entries: [Entry], in data: Data) throws -> Data {
        var written = Data()
        for entry in entries { written.append(try chunk(for: entry)) }
        return try rewriting(data, dropping: Set(entries.map(\.keyword)), inserting: written)
    }

    /// A copy of `data` with every text chunk under `keywords` gone from its header and
    /// nothing put in their place: a poster borrowed from another file, about to be given a
    /// record of its own.
    public static func removing(_ keywords: Set<String>, from data: Data) throws -> Data {
        try rewriting(data, dropping: keywords, inserting: Data())
    }

    private static func rewriting(_ data: Data, dropping dropped: Set<String>, inserting written: Data) throws -> Data {
        let bytes = Array(data)
        let spans = try spans(in: bytes)
        guard let image = spans.first(where: { $0.type == "IDAT" }) else {
            throw Failure.noImageData
        }
        var result = Data(capacity: bytes.count + written.count)
        result.append(contentsOf: bytes[0..<8])
        for span in spans where span.start < image.start {
            guard !isText(span, keywordIn: dropped, of: bytes) else { continue }
            result.append(contentsOf: bytes[span.start..<(span.body.upperBound + 4)])
        }
        result.append(written)
        result.append(contentsOf: bytes[image.start...])
        return result
    }

    /// Whether `span` is a text chunk filed under one of the keywords being rewritten.
    ///
    /// The keyword is read from the chunk's own bytes rather than through `decode`, which
    /// answers nil for compressed text. A chunk this reader cannot read is still a chunk under
    /// that keyword, and leaving it behind would mean two of them.
    private static func isText(
        _ span: Span,
        keywordIn keywords: Set<String>,
        of bytes: [UInt8]
    ) -> Bool {
        guard span.type == "tEXt" || span.type == "iTXt" else { return false }
        let body = Array(bytes[span.body])
        guard let separator = body.firstIndex(of: 0),
              let keyword = String(bytes: body[..<separator], encoding: .isoLatin1)
        else { return false }
        return keywords.contains(keyword)
    }
}

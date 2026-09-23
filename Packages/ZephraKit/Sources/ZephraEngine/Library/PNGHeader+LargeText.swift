import Foundation

/// The one kind of chunk the seeking walk has to look inside before it knows whether to read it:
/// a text chunk past `PNGHeader.bodyReadLimit`.
///
/// The keyword comes first — the bytes up to the first NUL, at most 79 by the PNG specification —
/// and decides it. A reference picture (`zephra:reference`, `zephra:reference.2` through `.10`)
/// is stepped over, which is what the walk seeks for. Anything else is read whole up to
/// `PNGHeader.textReadLimit`, because a `zephra:generation` chunk over the body limit is a picture
/// with a long prompt, and stepping over it would drop that picture out of the library. Past the
/// cap it is stepped over too and its keyword noted in `skippedText`.
extension PNGHeader {
    /// The chunk types that carry a keyword first and that `absorb` reads as text.
    static let textTypes: Set<String> = ["tEXt", "iTXt"]

    /// The longest keyword the specification allows, and the NUL after it.
    static let keywordPrefix = 80

    /// Whether `keyword` names a reference picture's chunk, the one text Zephra writes that is
    /// large by nature.
    static func isReferenceKeyword(_ keyword: String) -> Bool {
        let base = GenerationRecord.referenceKeyword
        return keyword == base || keyword.hasPrefix(base + ".")
    }

    /// Reads, or steps over, the `length`-byte body of a `type` text chunk at the handle's
    /// offset, leaving the handle at the chunk's CRC.
    static func readLargeText(
        type: String, length: Int, from handle: FileHandle, into found: inout Builder
    ) throws {
        let start = try handle.offset()
        guard let head = try handle.read(upToCount: min(keywordPrefix, length)),
              head.count == min(keywordPrefix, length)
        else { throw PNGTextChunks.Failure.truncated }
        let keyword = String(decoding: head.prefix { $0 != 0 }, as: UTF8.self)
        let isReference = isReferenceKeyword(keyword)
        guard !isReference, length <= textReadLimit else {
            if !isReference { found.skippedText.insert(keyword) }
            try handle.seek(toOffset: start + UInt64(length))
            return
        }
        let rest = length - head.count
        guard let tail = try handle.read(upToCount: rest), tail.count == rest else {
            throw PNGTextChunks.Failure.truncated
        }
        found.absorb(type: type, body: Array(head) + Array(tail))
    }
}

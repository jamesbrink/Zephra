import Foundation
import ZephraCore

/// The reference pictures filed beside a record, in numbered chunks of their own.
///
/// Picture 1 is `zephra:reference` and has been since there was one, so every build that came
/// before this one, exiftool, and `reference(in:)` still read it with no change at all. Pictures
/// 2 and up are that keyword suffixed with their 1-based position: there is no `.1`, so no
/// suffix is ambiguous with the unsuffixed chunk. A chunk per picture rather than one chunk
/// holding a list, because `PNGTextChunks.read` is keyed by keyword and several pictures cannot
/// share one.
extension GenerationRecord {
    /// The keyword picture `index` (0-based) is filed under.
    public static func referenceKeyword(at index: Int) -> String {
        index == 0 ? referenceKeyword : "\(referenceKeyword).\(index + 1)"
    }

    /// Every keyword a reference picture may occupy, which is what a stripper removes.
    public static var allReferenceKeywords: [String] {
        (0..<ReferenceLimits.maximumPictures).map { referenceKeyword(at: $0) }
    }

    /// The reference pictures filed beside the record in `data`, in the order the model read
    /// them, or none where the file carries no record or no picture.
    ///
    /// Each chunk's length is checked against the record, as the single picture's always has
    /// been: a chunk some other tool rewrote is dropped rather than trusted. A failure **stops**
    /// and the pictures before it are returned, so a file whose fourth chunk went bad is an edit
    /// of three pictures rather than of none — the order is what a model reads them in, and a
    /// picture that arrived in somebody else's place would be worse than a picture missing.
    public static func references(in data: Data) -> [ReferencePicture] {
        guard let record = read(from: data), let text = try? PNGTextChunks.read(from: data) else {
            return []
        }
        return record.references(in: text)
    }

    /// The same, for a caller that has already read the file's text chunks — a scan, which
    /// reads every keyword out of the header in one pass.
    public func references(in text: [String: String]) -> [ReferencePicture] {
        let counts = referenceByteCounts ?? referenceBytes.map { [$0] } ?? []
        let origins = referenceOrigins ?? [referenceOrigin]
        var pictures: [ReferencePicture] = []
        for (index, expected) in counts.enumerated() {
            guard let encoded = text[Self.referenceKeyword(at: index)],
                  let bytes = Data(base64Encoded: encoded),
                  bytes.count == expected
            else { break }
            let origin = index < origins.count ? origins[index] : nil
            pictures.append(ReferencePicture(data: bytes, origin: origin))
        }
        return pictures
    }

    /// The base64 each reference chunk holds, unchecked and undecoded, in order.
    ///
    /// What an upscale carries through: the result keeps its parent's chunks verbatim rather
    /// than decoding and re-encoding them, so the counts in the record it inherits still match
    /// what the chunks actually carry.
    public static func referenceTexts(in text: [String: String]) -> [String] {
        var texts: [String] = []
        for keyword in allReferenceKeywords {
            guard let encoded = text[keyword] else { break }
            texts.append(encoded)
        }
        return texts
    }
}

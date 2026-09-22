import Foundation
import ZephraCore

/// Getting the record into a PNG and back out of it.
extension GenerationRecord {
    /// `image`'s PNG bytes with its record inside them.
    ///
    /// Three chunks go in: the JSON under Zephra's own keyword, a standard `Software` line, and
    /// a `Description` holding the prompt, so the Finder's inspector, Preview, and exiftool all
    /// show something worth reading without knowing anything about Zephra. An edited image
    /// carries a fourth, the reference it was edited from, so that selecting it later puts the
    /// picture back and an exported edit can reproduce itself.
    ///
    /// Idempotent: bytes that already carry a record come back untouched, so exporting an image
    /// that was itself restored from disk never doubles the chunk up.
    public static func embedded(in image: GeneratedImage) throws -> Data {
        try embedded(
            GenerationRecord(image), in: image.pngData, prompt: image.settings.prompt,
            referenceTexts: image.settings.referenceImages
                .filter(\.hasPixels)
                .map { $0.data.base64EncodedString() })
    }

    /// `pngData` with `record` and its companions inside it, for a caller that has the record
    /// rather than a `GeneratedImage`: an upscale, whose record is derived from its parent's.
    ///
    /// `referenceTexts` are the base64 strings the numbered `zephra:reference` chunks hold, in
    /// order, passed through untouched. An upscale hands over the parent's own texts verbatim
    /// rather than decoding and re-encoding them, so the record's counts still match what the
    /// chunks actually carry.
    ///
    /// The one place the chunk list is spelled out, so the two callers cannot drift apart.
    public static func embedded(
        _ record: GenerationRecord, in pngData: Data, prompt: String, referenceTexts: [String]
    ) throws -> Data {
        let existing = try PNGTextChunks.read(from: pngData)
        guard existing[keyword] == nil else { return pngData }
        var entries: [PNGTextChunks.Entry] = [
            (keyword: keyword, text: try json(for: record)),
            (keyword: "Software", text: software),
        ]
        let described = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !described.isEmpty {
            entries.append((keyword: "Description", text: described))
        }
        for (index, text) in referenceTexts.prefix(ReferenceLimits.maximumPictures).enumerated() {
            entries.append((keyword: referenceKeyword(at: index), text: text))
        }
        return try PNGTextChunks.inserting(entries, into: pngData)
    }

    /// The record inside a PNG, or nil when the file carries none, is not a PNG at all, or
    /// claims a version this build was not written to read. A foreign PNG dropped into the
    /// library reads as nil, which is how the library comes to ignore it.
    public static func read(from data: Data) -> GenerationRecord? {
        guard let text = try? PNGTextChunks.read(from: data) else { return nil }
        return decode(from: text)
    }

    /// The record in a PNG's text chunks, which a scan already has in hand: it reads every
    /// keyword out of the header in one pass and asks each type to pick out its own.
    public static func decode(from text: [String: String]) -> GenerationRecord? {
        guard let json = text[keyword],
              let record = try? decoder().decode(Self.self, from: Data(json.utf8)),
              record.version <= currentVersion
        else { return nil }
        return record
    }

    /// The first reference image filed beside the record in `data`, or nil when the file
    /// carries none, the chunk does not decode, or its length disagrees with the record: a
    /// chunk some other tool rewrote is dropped rather than trusted.
    ///
    /// The one picture most of the app reads, over `references(in:)`, which is every one of
    /// them in the order the model read them.
    public static func reference(in data: Data) -> Data? {
        references(in: data).first?.data
    }

    /// The JSON one record is stored as: sorted keys and ISO 8601 dates, so a file written
    /// twice from the same image is byte for byte the same file.
    static func json(for record: GenerationRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(record), as: UTF8.self)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The `Software` line: the app's marketing version when there is a bundle to ask, and the
    /// bare name when there is not, as in a test run or a command-line tool.
    private static var software: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        guard let version = version as? String, !version.isEmpty else { return "Zephra" }
        return "Zephra \(version)"
    }
}

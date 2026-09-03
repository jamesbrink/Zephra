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
        let existing = try PNGTextChunks.read(from: image.pngData)
        guard existing[keyword] == nil else { return image.pngData }
        var entries: [PNGTextChunks.Entry] = [
            (keyword: keyword, text: try json(for: GenerationRecord(image))),
            (keyword: "Software", text: software),
        ]
        let prompt = image.settings.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            entries.append((keyword: "Description", text: prompt))
        }
        if let reference = image.settings.referenceImage {
            entries.append((keyword: referenceKeyword, text: reference.base64EncodedString()))
        }
        return try PNGTextChunks.inserting(entries, into: image.pngData)
    }

    /// The record inside a PNG, or nil when the file carries none, is not a PNG at all, or
    /// claims a version this build was not written to read. A foreign PNG dropped into the
    /// library reads as nil, which is how the library comes to ignore it.
    public static func read(from data: Data) -> GenerationRecord? {
        guard let text = try? PNGTextChunks.read(from: data),
              let json = text[keyword],
              let record = try? decoder().decode(Self.self, from: Data(json.utf8)),
              record.version <= currentVersion
        else { return nil }
        return record
    }

    /// The reference image filed beside the record in `data`, or nil when the file carries
    /// none, the chunk does not decode, or its length disagrees with the record: a chunk some
    /// other tool rewrote is dropped rather than trusted.
    public static func reference(in data: Data) -> Data? {
        guard let record = read(from: data), let expected = record.referenceBytes,
              let text = try? PNGTextChunks.read(from: data),
              let encoded = text[referenceKeyword],
              let reference = Data(base64Encoded: encoded),
              reference.count == expected
        else { return nil }
        return reference
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

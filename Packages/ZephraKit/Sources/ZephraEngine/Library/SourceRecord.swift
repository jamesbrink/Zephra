import Foundation

/// Where an imported picture came from, written inside the copy Zephra keeps.
///
/// The counterpart of `GenerationRecord` for the other half of the library: an image Zephra did
/// not make but can generate from. Same principle — the file carries its own provenance, so a
/// source picture is still recognisable after it has been moved, renamed, or copied to another
/// Mac, and the folder needs no index to be read back.
public struct SourceRecord: Hashable, Sendable, Codable {
    /// The PNG text keyword the JSON is filed under.
    public static let keyword = "zephra:source"
    /// The shape written today; a file claiming a higher version is left alone.
    public static let currentVersion = 1

    /// Which shape this record is in.
    public var version: Int
    /// When the picture was brought into the library.
    public var importedAt: Date
    /// What the file was called where it came from, which is the only name worth showing.
    public var originalFileName: String
    /// Pixel width of the imported copy.
    public var width: Int
    /// Pixel height of the imported copy.
    public var height: Int
    /// A digest of the original bytes, so the same picture imported twice can be recognised.
    public var digest: String

    /// Records one imported picture.
    public init(
        importedAt: Date,
        originalFileName: String,
        width: Int,
        height: Int,
        digest: String
    ) {
        self.version = Self.currentVersion
        self.importedAt = importedAt
        self.originalFileName = originalFileName
        self.width = width
        self.height = height
        self.digest = digest
    }

    /// The record in a PNG's text chunks, or nil when there is none, it is unreadable, or it
    /// claims a version this build was not written to read.
    public static func decode(from text: [String: String]) -> SourceRecord? {
        guard let json = text[keyword] else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let record = try? decoder.decode(Self.self, from: Data(json.utf8)),
              record.version <= currentVersion
        else { return nil }
        return record
    }

    /// The chunk entry this record is written as: sorted keys and ISO 8601 dates, so the same
    /// record always writes the same bytes.
    public func entry() throws -> PNGTextChunks.Entry {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (keyword: Self.keyword, text: String(decoding: try encoder.encode(self), as: UTF8.self))
    }
}

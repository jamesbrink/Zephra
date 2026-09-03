import Foundation

/// What the person using Zephra said about an image, written inside the PNG beside its record.
///
/// A second chunk rather than more fields on `GenerationRecord`, because the two answer
/// different questions and change at different rates. The record is provenance: what produced
/// the image, written once and never touched again. This is opinion: favourite, tags, which
/// albums it is in, rewritten whenever a checkbox is ticked. Keeping them apart means marking a
/// favourite never rewrites the provenance, and an image copied to another Mac carries both.
public struct LibraryAnnotation: Hashable, Sendable, Codable {
    /// The PNG text keyword the JSON is filed under.
    public static let keyword = "zephra:library"
    /// The shape written today. A file claiming a higher version reads as nothing rather than
    /// being guessed at, so this build never invents opinions a later one recorded.
    public static let currentVersion = 1

    /// One album an image belongs to.
    ///
    /// The name travels with the id so a folder of images carries its own albums: the manifest
    /// in the library root is a cache that can be rebuilt from the pictures themselves.
    public struct Membership: Hashable, Sendable, Codable, Identifiable {
        /// The album's stable identity, which is what a rename does not change.
        public let id: UUID
        /// The album's name as it stood when this image was added to it.
        public var name: String

        /// Records membership of one album.
        public init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// Which shape this annotation is in.
    public var version: Int
    /// Whether the image is a favourite.
    public var isFavourite: Bool
    /// The tags it carries, in the order they were added.
    public var tags: [String]
    /// The albums it belongs to.
    public var albums: [Membership]

    /// An annotation, empty by default: nothing has been said about the image yet.
    public init(isFavourite: Bool = false, tags: [String] = [], albums: [Membership] = []) {
        self.version = Self.currentVersion
        self.isFavourite = isFavourite
        self.tags = tags
        self.albums = albums
    }

    /// Nothing said about the image, which is what an unannotated file reads as.
    public static let none = LibraryAnnotation()

    /// Whether anything at all has been said.
    public var isEmpty: Bool { !isFavourite && tags.isEmpty && albums.isEmpty }

    /// The annotation in a PNG's text chunks, or `none` when there is none, it is unreadable,
    /// or it claims a version this build was not written to read.
    public static func decode(from text: [String: String]) -> LibraryAnnotation {
        guard let json = text[keyword],
              let annotation = try? JSONDecoder().decode(Self.self, from: Data(json.utf8)),
              annotation.version <= currentVersion
        else { return none }
        return annotation
    }

    /// The chunk entry this annotation is written as.
    ///
    /// Sorted keys, so a file written twice from the same annotation is byte for byte the same
    /// file, which is what lets a repeated write be recognised as a no-op.
    public func entry() throws -> PNGTextChunks.Entry {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (keyword: Self.keyword, text: String(decoding: try encoder.encode(self), as: UTF8.self))
    }
}

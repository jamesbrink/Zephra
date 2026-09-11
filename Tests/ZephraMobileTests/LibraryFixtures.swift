import Foundation
import ZephraLinkProtocol

@testable import ZephraMobile

/// Library entries to hand the cache, built from the bundle's own preview fixture.
///
/// Built from the fixture rather than from a literal on purpose, and it is the same purpose
/// `PreviewFixtureTests` serves: an entry the cache is tested against is then an entry a Mac
/// would actually send, decoded by the wire's own decoder. It is also what lets these suites
/// stay clear of `ZephraEngine` — the record and the annotation inside an entry are that
/// module's types, and the phone may not import it.
enum LibraryFixtures {
    /// The fixture's first picture, which every entry below is a copy of.
    static var template: LibraryEntry {
        guard let first = MobilePreview.library().first else {
            fatalError("the preview library fixture is missing from the test host's bundle")
        }
        return first
    }

    /// The fixture's clip, for the scope that only wants those.
    static var clip: LibraryEntry {
        guard let video = MobilePreview.library().first(where: \.isVideo) else {
            fatalError("the preview library fixture has no clip in it")
        }
        return video
    }

    /// One entry, named and dated as asked, with a fingerprint that follows its facts the way
    /// a real one's does.
    static func entry(
        _ fileName: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_772_000_000),
        modifiedAt: Date? = nil,
        fileSize: Int = 1_000_000,
        prompt: String? = nil,
        favourite: Bool = false,
        tags: [String] = [],
        isVideo: Bool = false
    ) -> LibraryEntry {
        var entry = isVideo ? clip : template
        entry.fileName = fileName
        entry.createdAt = createdAt
        entry.contentModifiedAt = modifiedAt ?? createdAt
        entry.fileSize = fileSize
        entry.annotation.isFavourite = favourite
        entry.annotation.tags = tags
        if let prompt { entry.record?.prompt = prompt }
        entry.version = LibraryEntry.version(
            fileName: entry.fileName, contentModifiedAt: entry.contentModifiedAt,
            fileSize: entry.fileSize)
        return entry
    }

    /// The same entry as the cache holds it.
    static func cached(
        _ fileName: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_772_000_000),
        modifiedAt: Date? = nil,
        fileSize: Int = 1_000_000,
        prompt: String? = nil,
        favourite: Bool = false,
        tags: [String] = [],
        isVideo: Bool = false
    ) -> CachedEntry {
        CachedEntry(
            entry(
                fileName, createdAt: createdAt, modifiedAt: modifiedAt, fileSize: fileSize,
                prompt: prompt, favourite: favourite, tags: tags, isVideo: isVideo))
    }
}

import Foundation
import ZephraLinkProtocol

/// One picture of the Mac's library as the phone keeps it: the wire's own entry, on disk.
///
/// It wraps `LibraryEntry` rather than copying its fields, for two reasons. The record and the
/// annotation inside it are `ZephraEngine` types, and the phone may not import that module —
/// the layering rule is the whole point of the companion, so nothing here ever spells one of
/// those names. And a cached entry that *is* the wire entry can never drift from what a Mac
/// would send: the coding below is transparent, so a file in the cache is byte for byte the
/// JSON that arrived, and `PreviewFixtureTests`' argument applies to the cache as well.
///
/// The facts the surfaces need are lifted out as scalars, which is all a view ever reads.
nonisolated struct CachedEntry: Codable, Hashable, Identifiable, Sendable {
    /// The entry exactly as the Mac published it.
    let entry: LibraryEntry
    /// Everything the search box matches against, folded once when the entry is taken in: the
    /// prompt, the tags, the seed and the model. Folding on every keystroke instead would be a
    /// pass over the whole library per character typed.
    let searchKey: String

    /// The file's name is its identity, here as on the Mac and on the wire.
    var id: String { entry.fileName }

    /// Takes one entry into the cache.
    init(_ entry: LibraryEntry) {
        self.entry = entry
        searchKey = Self.key(for: entry)
    }

    /// The file's name inside the Mac's library folder.
    var fileName: String { entry.fileName }
    /// The fingerprint of the file as the Mac last saw it, which is what makes a cached
    /// thumbnail still the right one.
    var version: String { entry.version }
    /// When the file last changed on disk, which is half of what makes it stale.
    var contentModifiedAt: Date { entry.contentModifiedAt }
    /// How many bytes the file is, which is the other half.
    var fileSize: Int { entry.fileSize }
    /// Whether the picture is a clip's poster.
    var isVideo: Bool { entry.isVideo }
    /// Pixels across.
    var width: Int { entry.width }
    /// Pixels down.
    var height: Int { entry.height }
    /// When it was made, which is the day it is filed under.
    var createdAt: Date { entry.createdAt }
    /// Whether it is a favorite.
    var isFavourite: Bool { entry.annotation.isFavourite }
    /// The tags it carries, in the order they were added.
    var tags: [String] { entry.annotation.tags }
    /// What it was asked to draw, or an empty string for a file Zephra did not make.
    var prompt: String { entry.record?.prompt ?? "" }
    /// The model that made it, or nil for an import.
    var modelID: String? { entry.record?.modelID }
    /// How many times larger than its parent it is, when it is an upscale.
    var upscaleFactor: Int? { entry.record?.upscaleFactor }
    /// How long the clip plays, when it is one.
    var videoSeconds: Double? {
        guard isVideo, let frames = entry.record?.frameCount, let rate = entry.record?.frameRate,
            rate > 0
        else { return nil }
        return Double(frames) / rate
    }

    /// The start of the local day it was made on, which is the section it belongs to.
    var day: Date { Calendar.current.startOfDay(for: createdAt) }

    /// What VoiceOver reads, and what a file with no prompt is listed as.
    var label: String { prompt.isEmpty ? fileName : prompt }

    /// Whether the file behind this entry has moved since the Mac last described it.
    ///
    /// `LibraryEntry.version` is the SHA of exactly (name, modification time, size), so the
    /// version alone answers this; the two facts are compared beside it because a version is a
    /// truncated digest and the facts are free. An annotation edit rewrites the PNG, so its
    /// modification time moves and its version with it — which is why favoriting a picture on
    /// the Mac reaches the phone at all.
    func isStale(against remote: LibraryEntry) -> Bool {
        version != remote.version || contentModifiedAt != remote.contentModifiedAt
            || fileSize != remote.fileSize
    }

    /// The same entry with its annotation changed, for an optimistic edit not yet answered.
    ///
    /// The version is left alone: the Mac decides what a file's fingerprint is, and inventing
    /// one here would make the next sync believe the cache was already current.
    func annotated(favourite: Bool? = nil, tags: [String]? = nil) -> CachedEntry {
        var changed = entry
        if let favourite { changed.annotation.isFavourite = favourite }
        if let tags { changed.annotation.tags = tags }
        return CachedEntry(changed)
    }

    /// The cached file is the wire's JSON and nothing around it.
    init(from decoder: any Decoder) throws {
        self.init(try LibraryEntry(from: decoder))
    }

    func encode(to encoder: any Encoder) throws {
        try entry.encode(to: encoder)
    }

    /// Everything one entry is searched by, folded the way the Mac folds it: case and
    /// diacritics dropped, so "cafe" finds "Café" and "qwen" finds the model.
    private static func key(for entry: LibraryEntry) -> String {
        var parts = [entry.fileName]
        if let record = entry.record {
            parts.append(record.prompt)
            parts.append(record.modelID)
            parts.append(String(record.seed))
        }
        parts.append(contentsOf: entry.annotation.tags)
        return folded(parts.joined(separator: " "))
    }

    /// One spelling of "the same text", used on both sides of every match.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

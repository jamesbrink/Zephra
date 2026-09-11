import Foundation
import ZephraEngine
import ZephraLinkProtocol

/// The library folder as the phone lists it.
///
/// Recently Deleted is left out of every listing here, for the reason `LibraryIndex.item(named:)`
/// skips it: a name reused by a picture in the trash is not the picture anything else means, and
/// a phone offering to open one would be offering something the Mac's own grid keeps behind a
/// sidebar row. `libraryCount` and `libraryPage` therefore agree with each other.
///
/// The version is `LibraryEntry`'s own rule over the three facts `LibraryScan` re-reads a file
/// on, so an entry's fingerprint moves exactly when the Mac thinks the file moved and a phone's
/// cached thumbnail stays good until it does.
public enum LibraryEntryProjection {
    /// Every picture a phone may see, newest first.
    public static func listing(_ items: [LibraryItem]) -> [LibraryItem] {
        items
            .filter { $0.collection != .recentlyDeleted }
            .sorted { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
    }

    /// One picture as a row.
    public static func entry(_ item: LibraryItem) -> LibraryEntry {
        LibraryEntry(
            fileName: item.fileName,
            record: item.provenance.record,
            annotation: item.annotation,
            isVideo: item.isVideo,
            createdAt: item.createdAt,
            width: item.size.width,
            height: item.size.height,
            fileSize: Int(item.fileSize),
            contentModifiedAt: item.contentModifiedAt)
    }

    /// One window onto a listing, clamped to what it actually holds.
    public static func page(_ items: [LibraryItem], offset: Int, limit: Int) -> LibraryPage {
        let start = min(max(offset, 0), items.count)
        let end = min(start + max(limit, 0), items.count)
        return LibraryPage(
            entries: items[start..<end].map(entry), offset: start, total: items.count)
    }
}

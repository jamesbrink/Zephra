import Foundation

/// Reading the library's folders into items, cheaply enough to do it often.
///
/// Two operations, and the difference between them is the point. `fingerprint()` is one
/// directory listing per folder and no file is opened: it answers "has anything changed?" for a
/// thousand images in a millisecond, which is what a folder watch fires into. `rescan(known:)`
/// opens only the files whose modification date or size has moved, so the answer to a change in
/// one file costs one header read rather than a thousand.
///
/// A value type with no state of its own, so it can be handed to a background task and run
/// there while the interface holds the items it produced.
public struct LibraryScan: Sendable {
    /// The folders being scanned.
    public let library: ImageLibrary
    /// Where the day starts, which decides which day an image is grouped under. A parameter
    /// only so a test can pin a time zone.
    public let calendar: Calendar

    /// Scans one library's folders.
    public init(library: ImageLibrary, calendar: Calendar = .current) {
        self.library = library
        self.calendar = calendar
    }

    /// A number that changes when any file in any of the library's folders is added, removed,
    /// renamed, resized, or rewritten, and does not change otherwise.
    ///
    /// Order-independent, because a directory listing's order is not something to rely on, and
    /// meaningful only within a run: it is compared with the last one this process took, never
    /// stored. A folder watch fires on any write in the directory, including ones Zephra made
    /// itself, so this is what stops most of them turning into a rescan.
    public func fingerprint() -> Int {
        var combined: UInt64 = 0
        for root in library.scanRoots {
            for listing in listings(in: root.url) {
                // The whole path, not the file name: moving an image to Recently Deleted keeps
                // its name, its size and its date, and has to read as a change.
                var hash = Self.offsetBasis
                Self.mix(listing.url.path(percentEncoded: false), into: &hash)
                Self.mix(String(listing.modifiedAt.timeIntervalSince1970), into: &hash)
                Self.mix(String(listing.size), into: &hash)
                combined = combined &+ hash
            }
        }
        return Int(bitPattern: UInt(combined))
    }

    /// Every image in the library, reusing what `known` already holds.
    ///
    /// A file whose modification date and size are both unchanged is taken from `known`
    /// verbatim, annotation included, so a scan after one favourite is toggled reads exactly
    /// one file. Anything Zephra cannot read the provenance of — a foreign PNG dropped into the
    /// folder, or one written by a build newer than this — is left out rather than shown with
    /// invented settings.
    public func rescan(known: [LibraryItem.ID: LibraryItem] = [:]) -> [LibraryItem] {
        var items: [LibraryItem] = []
        for root in library.scanRoots {
            for listing in listings(in: root.url) {
                let id = listing.url.path(percentEncoded: false)
                if let existing = known[id],
                   existing.collection == root.collection,
                   existing.contentModifiedAt == listing.modifiedAt,
                   existing.fileSize == listing.size {
                    items.append(existing)
                } else if let item = item(listing, in: root.collection) {
                    items.append(item)
                }
            }
        }
        return items
    }

    /// One file as the listing sees it, before anything is opened.
    struct Listing: Sendable {
        let url: URL
        let modifiedAt: Date
        let size: Int64
    }

    /// FNV-1a, which is small, has no dependencies, and does not change between runs the way a
    /// seeded `Hasher` does.
    private static let offsetBasis: UInt64 = 14_695_981_039_346_656_037

    private static func mix(_ text: String, into value: inout UInt64) {
        for byte in text.utf8 {
            value = (value ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

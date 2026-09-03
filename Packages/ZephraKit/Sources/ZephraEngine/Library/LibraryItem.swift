import Foundation

/// One file in the library, as everything above the file system sees it.
///
/// Identity is the standardized path, not a UUID: the file is the record, so two scans of the
/// same folder produce the same identities and nothing has to be kept in step. The cost is that
/// renaming a file in the Finder reads as a delete and an add, which is exactly what it is.
///
/// `searchKey` and `day` are computed once here rather than per keystroke: a search over ten
/// thousand images is a substring test against a string that already exists.
public struct LibraryItem: Identifiable, Hashable, Sendable {
    /// The standardized file path, which is what makes an item the same item across scans.
    public typealias ID = String

    /// The standardized path of the file.
    public let id: ID
    /// Where the file is.
    public let url: URL
    /// Which folder of the library it was found in.
    public let collection: LibraryCollection
    /// What produced it.
    public let provenance: LibraryProvenance
    /// What the user has said about it. Changed through `withAnnotation(_:)`, which keeps
    /// `searchKey` in step with the tags.
    public private(set) var annotation: LibraryAnnotation
    /// Bytes on disk, for the inspector's File row.
    public let fileSize: Int64
    /// The file's modification date, which is what a rescan compares to decide what to re-read.
    public let contentModifiedAt: Date
    /// Everything searchable about the item, folded once so matching is a substring test.
    public private(set) var searchKey: String
    /// The start of the local day the image was made on, which is what the grid groups by.
    public let day: Date

    /// Describes one file. `calendar` decides where the day starts, and is a parameter only so
    /// a test can pin a time zone.
    public init(
        url: URL,
        collection: LibraryCollection,
        provenance: LibraryProvenance,
        annotation: LibraryAnnotation = .none,
        fileSize: Int64,
        contentModifiedAt: Date,
        calendar: Calendar = .current
    ) {
        let standardized = url.standardizedFileURL
        self.id = standardized.path(percentEncoded: false)
        self.url = standardized
        self.collection = collection
        self.provenance = provenance
        self.annotation = annotation
        self.fileSize = fileSize
        self.contentModifiedAt = contentModifiedAt
        self.searchKey = Self.searchKey(
            provenance: provenance, annotation: annotation, fileName: standardized.lastPathComponent)
        self.day = calendar.startOfDay(for: provenance.createdAt)
    }

    /// The same item with a different annotation, and a search key that agrees with it.
    public func withAnnotation(_ annotation: LibraryAnnotation) -> LibraryItem {
        var copy = self
        copy.annotation = annotation
        copy.searchKey = Self.searchKey(
            provenance: provenance, annotation: annotation, fileName: url.lastPathComponent)
        return copy
    }

    /// Text made comparable: case, accents and full-width forms folded away, so "cafe" finds
    /// "Café" and the same folding is applied to what the user types.
    public static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Everything a search should match, in one folded string.
    ///
    /// The seed goes in twice, as the decimal number the record stores and as the short hex
    /// label the interface shows, because either is a reasonable thing to paste into a search
    /// box and only one of them is on screen.
    private static func searchKey(
        provenance: LibraryProvenance,
        annotation: LibraryAnnotation,
        fileName: String
    ) -> String {
        var parts: [String] = []
        switch provenance {
        case .generated(let record):
            parts.append(record.prompt)
            if let negative = record.negativePrompt { parts.append(negative) }
            parts.append(String(record.seed))
            parts.append(record.seed.shortSeedLabel)
        case .imported(let source):
            parts.append(source.originalFileName)
        }
        parts.append(fileName)
        parts.append(contentsOf: annotation.tags)
        return folded(parts.joined(separator: "\n"))
    }
}

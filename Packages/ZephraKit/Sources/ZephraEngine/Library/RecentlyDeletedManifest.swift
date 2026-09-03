import Foundation

/// When each image in Recently Deleted was deleted, kept in one hidden file beside them.
///
/// The file system has no field for it — a move keeps the creation date and updates nothing
/// useful — so the one fact the grace period needs is written down. Nothing else is: the images
/// themselves are the collection, and a name in here with no file beside it is simply dropped.
public struct RecentlyDeletedManifest: Hashable, Sendable, Codable {
    /// The file it is kept in, inside the Recently Deleted folder.
    public static let fileName = ".zephra-deleted.json"
    /// The shape written today; one claiming a higher version reads as empty.
    public static let currentVersion = 1
    /// How long a deleted image is kept, matching what Photos does.
    public static let grace: TimeInterval = 30 * 24 * 60 * 60

    /// One deleted image.
    public struct Entry: Hashable, Sendable, Codable {
        /// The file's name inside the Recently Deleted folder, which is what identifies it.
        public var fileName: String
        /// When it was deleted, which is when its thirty days started.
        public var deletedAt: Date

        /// Records one deletion.
        public init(fileName: String, deletedAt: Date) {
            self.fileName = fileName
            self.deletedAt = deletedAt
        }
    }

    /// Which shape this manifest is in.
    public var version: Int
    /// The deletions recorded, one per file.
    public var entries: [Entry]

    /// A manifest listing `entries`.
    public init(entries: [Entry] = []) {
        self.version = Self.currentVersion
        self.entries = entries
    }

    /// When `fileName` was deleted, or nil for a file nobody wrote down.
    public func deletedAt(_ fileName: String) -> Date? {
        entries.first { $0.fileName == fileName }?.deletedAt
    }

    /// Records a deletion, replacing any earlier entry under the same name.
    public mutating func record(_ fileName: String, at date: Date) {
        entries.removeAll { $0.fileName == fileName }
        entries.append(Entry(fileName: fileName, deletedAt: date))
    }

    /// Forgets a file, because it was restored or purged.
    public mutating func forget(_ fileName: String) {
        entries.removeAll { $0.fileName == fileName }
    }
}

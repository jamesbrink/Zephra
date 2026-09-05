import Foundation
import ZephraEngine

/// Which thumbnail a view is currently asking for: one image, in one state, at one size.
///
/// It exists to be the identity of a `.task`. SwiftUI restarts a task when its id changes, so
/// naming every half here is what makes a cell reload when the slider crosses into the next
/// bucket, or when the file under it is rewritten — every annotation write is one — and only
/// then: a cell whose image, file and size are all unchanged keeps the pixels it has through
/// any number of redraws. The state is the same pair `ThumbnailKey` digests, so a request
/// that changes is exactly a key that misses.
nonisolated struct ThumbnailRequest: Hashable, Sendable {
    /// The image's path, which is a library item's identity.
    let id: LibraryItem.ID
    /// When the file's content last changed.
    let modifiedAt: Date
    /// How many bytes the file holds.
    let fileSize: Int64
    /// The bucket to bake at, or nil where no cache has been supplied at all.
    let size: ThumbnailSize?

    /// One request, for the item as it is right now.
    init(_ item: LibraryItem, _ size: ThumbnailSize?) {
        id = item.id
        modifiedAt = item.contentModifiedAt
        fileSize = item.fileSize
        self.size = size
    }
}

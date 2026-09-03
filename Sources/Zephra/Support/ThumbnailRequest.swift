/// Which thumbnail a view is currently asking for: one image at one size.
///
/// It exists to be the identity of a `.task`. SwiftUI restarts a task when its id changes, so
/// naming both halves here is what makes a cell reload when the slider crosses into the next
/// bucket, and only then — a cell whose image and size are both unchanged keeps the pixels it
/// has through any number of redraws.
nonisolated struct ThumbnailRequest: Hashable, Sendable {
    /// The image's path, which is a library item's identity.
    let id: LibraryItem.ID
    /// The bucket to bake at, or nil where no cache has been supplied at all.
    let size: ThumbnailSize?

    /// One request.
    init(_ id: LibraryItem.ID, _ size: ThumbnailSize?) {
        self.id = id
        self.size = size
    }
}

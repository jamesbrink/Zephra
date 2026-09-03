/// Which folder of the library a file was found in.
///
/// One collection per folder on disk, which is what keeps this honest: an image is in Recently
/// Deleted because it is in the `Recently Deleted` directory, not because a database says so.
/// Move it back in the Finder and the library agrees.
public enum LibraryCollection: String, Hashable, Sendable, CaseIterable {
    /// Images Zephra made, in the library root.
    case generated
    /// Images that were deleted and are waiting to be restored or purged.
    case recentlyDeleted
    /// Pictures imported to generate from, kept apart from the images generated.
    case sources
}

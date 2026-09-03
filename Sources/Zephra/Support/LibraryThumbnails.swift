import SwiftUI

/// The cache a thumbnail should ask, and the size it should ask for.
///
/// Two things rather than one because they change at different rates and for different reasons.
/// The cache is built once in the composition root; the size is whatever the pane showing the
/// thumbnails has decided — the grid's slider, or the fixed small bucket the sidebar's Today
/// row uses. Pairing them here means `LibraryThumbnail` reads one value and holds no opinion
/// about either.
struct LibraryThumbnails {
    /// Where the pixels come from.
    let cache: ThumbnailCache
    /// Which bucket to bake at.
    let size: ThumbnailSize

    /// A thumbnail source at one size.
    init(cache: ThumbnailCache, size: ThumbnailSize) {
        self.cache = cache
        self.size = size
    }
}

extension EnvironmentValues {
    /// Nil in a preview that has no cache, which is what makes a `LibraryThumbnail` draw its
    /// placeholder and nothing else rather than reach for a file that is not there.
    @Entry var libraryThumbnails: LibraryThumbnails?
}

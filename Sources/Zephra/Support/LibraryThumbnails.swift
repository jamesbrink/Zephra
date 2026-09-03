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
    /// How wide one cell is, in points. The slider's exact value, so the grid can lay itself
    /// out continuously; the bucket below is the coarse version that decides what to bake.
    let edge: CGFloat

    /// A thumbnail source for cells of `edge` points.
    init(cache: ThumbnailCache, edge: CGFloat) {
        self.cache = cache
        self.edge = edge
    }

    /// A thumbnail source at one fixed bucket, for a grid whose cells never change size.
    init(cache: ThumbnailCache, size: ThumbnailSize) {
        self.init(cache: cache, edge: size.points)
    }

    /// Which bucket to bake at for cells this wide.
    var size: ThumbnailSize { .bucket(forWidth: edge) }
}

extension EnvironmentValues {
    /// Nil in a preview that has no cache, which is what makes a `LibraryThumbnail` draw its
    /// placeholder and nothing else rather than reach for a file that is not there.
    @Entry var libraryThumbnails: LibraryThumbnails?
}

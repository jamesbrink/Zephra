import SwiftUI

/// Points the picker's grid at the app's own thumbnail cache, at a fixed small bucket.
///
/// A modifier of its own rather than a fourth stored property on `ReferencePickerGrid`, which
/// already holds its three: the same reason `TimelineTileGrid` reads the cache directly, except
/// here the read has to happen somewhere that is not the grid, because the grid's budget is
/// already spent on the selection, the confirm action, and the index.
struct ReferencePickerThumbnails: ViewModifier {
    @Environment(ThumbnailCache.self) private var thumbnails

    func body(content: Content) -> some View {
        content.environment(\.libraryThumbnails, LibraryThumbnails(cache: thumbnails, size: .small))
    }
}

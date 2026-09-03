import SwiftUI

/// Nothing to look at: a zero-height marker at the end of one day's images that starts baking
/// the thumbnails of the day below.
///
/// SwiftUI's lazy grids have no prefetch hook — a cell is built when it is about to be drawn,
/// which is far too late to decode a picture. A marker where the fold usually falls is the
/// closest thing there is: by the time the last row of a day is on screen, the next few rows
/// are already being made.
struct LibraryLookAhead: View {
    /// The images just below, in the order they will be wanted.
    let items: [LibraryItem]

    @Environment(\.libraryThumbnails) private var thumbnails

    var body: some View {
        Color.clear
            .frame(height: 0)
            .accessibilityHidden(true)
            .onAppear {
                guard let thumbnails, !items.isEmpty else { return }
                thumbnails.cache.warm(items, size: thumbnails.size)
            }
    }
}

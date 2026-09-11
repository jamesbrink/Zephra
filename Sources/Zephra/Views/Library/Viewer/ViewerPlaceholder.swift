import SwiftUI
import ZephraEngine
import ZephraStyle

/// What the viewer shows before the full-size decode lands: the grid's thumbnail, stretched
/// over a rectangle of the picture's own shape.
///
/// The shape is the point. `LibraryThumbnail` is a square, which is right for a grid cell and
/// wrong here: a square the pane's width overflowed the pane's height and sat under the bar.
/// A rectangle at the picture's aspect, fitted to the pane the way the finished picture will
/// be, means the picture lands in the rectangle its stand-in was filling, and nothing jumps.
struct ViewerPlaceholder: View {
    /// The image about to show.
    let item: LibraryItem

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(item.size.aspectRatio, contentMode: .fit)
            .overlay {
                LibraryThumbnail(item: item)
                    .scaledToFill()
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

#Preview("Placeholder") {
    ViewerPlaceholder(item: PreviewImages.library(count: 1).items[0])
        .frame(width: 600, height: 400)
        .background(Color.canvasBackground)
        .environment(\.libraryThumbnails, LibraryThumbnails(cache: ThumbnailCache(), edge: 168))
}

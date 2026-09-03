import SwiftUI
import ZephraEngine

/// Today's pictures as one wall of small squares, newest run first, with a dashed place for each
/// seed still to come at the top of it.
///
/// One grid for the whole day rather than one per run. A run of one picture in a grid of its
/// own left two thirds of the row empty and put a caption over every single square; here the
/// squares pack, and what any of them was asked for is one press away in the inspector or under
/// the pointer as a tooltip. The columns follow the sidebar's width, three across at its usual
/// size, the way Photos fills a column.
///
/// One list row rather than a row per tile, because the wall is a single object to scroll past
/// and a `List` that thought it held forty rows would put separators through it.
///
/// The ring is drawn here rather than by the tile, because being the picture the canvas is
/// showing is a fact about the file and not about which of the three kinds of tile is standing
/// in for it. A place still to be filled has no file and so is never ringed.
struct TimelineTileGrid: View {
    /// Every square of the day: the running run's, then the finished runs' newest first.
    let tiles: [TimelineTile]

    @Environment(GenerationStore.self) private var store
    @Environment(ThumbnailCache.self) private var thumbnails

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 4)], spacing: 4) {
            ForEach(tiles) { tile in
                RunTile(tile: tile)
                    .clipShape(shape)
                    .overlay {
                        if isShowing(tile) {
                            shape.strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .accessibilityAddTraits(isShowing(tile) ? .isSelected : [])
            }
        }
        .environment(\.libraryThumbnails, LibraryThumbnails(cache: thumbnails, size: .small))
        .padding(.vertical, 2)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous)
    }

    /// Whether this is the picture the canvas is showing, so the sidebar and the canvas agree
    /// about where you are.
    private func isShowing(_ tile: TimelineTile) -> Bool {
        guard let file = tile.fileURL, let current = store.current?.fileURL else { return false }
        return current.standardizedFileURL == file.standardizedFileURL
    }
}

#Preview("Two done, two to come") {
    let run = PreviewImages.run(of: 2)
    List {
        TimelineTileGrid(tiles: run.reversed().map { .fresh($0) } + [.pending(2), .pending(3)])
            .listRowBackground(Color.clear)
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 260)
    .environment(ImageCache())
    .environment(ThumbnailCache())
    .environment(GenerationStore.preview(state: .ready, images: run))
}

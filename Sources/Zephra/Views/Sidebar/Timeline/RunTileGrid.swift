import SwiftUI
import ZephraEngine

/// One run's seeds, two by two, in a single row of the sidebar's list.
///
/// One list row rather than a row per tile, because the grid is a single object to scroll past
/// and a `List` that thought it held four rows would put separators through it.
///
/// The ring is drawn here rather than by the tile, because being the picture the canvas is
/// showing is a fact about the file and not about which of the three kinds of tile is standing
/// in for it. A place still to be filled has no file and so is never ringed.
struct RunTileGrid: View {
    /// The run's squares, oldest seed first.
    let tiles: [TimelineTile]

    @Environment(GenerationStore.self) private var store
    @Environment(ThumbnailCache.self) private var thumbnails

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
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
        RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous)
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
        RunTileGrid(tiles: run.reversed().map { .fresh($0) } + [.pending(2), .pending(3)])
            .listRowBackground(Color.clear)
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 260)
    .environment(ImageCache())
    .environment(ThumbnailCache())
    .environment(GenerationStore.preview(state: .ready, images: run))
}

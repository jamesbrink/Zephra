import SwiftUI
import ZephraEngine

/// Today's pictures as a wall of small squares, newest run first, with a dashed place for each
/// seed still to come at the top of it.
///
/// One wall for the whole day rather than a grid per run, and one flow rather than a block per
/// run. A run of one picture in a grid of its own left two thirds of the row empty and put a
/// caption over every single square, and a batch in a block of its own ended its row early, so
/// a wall of batches and singles read as ragged. Here everything packs three across in run
/// order (`SessionTimeline.wall(of:)`); a run still reads as a run because its squares sit
/// together, and what any square was asked for is in the inspector or under the pointer.
///
/// One list row rather than a row per tile, because the wall is a single object to scroll past
/// and a `List` that thought it held forty rows would put separators through it.
struct TimelineTileGrid: View {
    /// The wall's squares, in the order they are laid.
    let tiles: [TimelineTile]

    @Environment(GenerationStore.self) private var store
    @Environment(ThumbnailCache.self) private var thumbnails

    /// Three across at the sidebar's usual width; four when it is dragged wide.
    private static let columns = [GridItem(.adaptive(minimum: 72), spacing: 4)]

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 4) {
            ForEach(tiles) { tile in
                WallSquare(tile: tile, isShowing: isShowing(tile))
            }
        }
        .environment(\.libraryThumbnails, LibraryThumbnails(cache: thumbnails, size: .small))
        .padding(.vertical, 2)
    }

    /// Whether this is the picture the canvas is showing, so the sidebar and the canvas agree
    /// about where you are.
    ///
    /// No square is, while the canvas is following the run: what is on the canvas then is the
    /// run, not a file, and the ring belongs to the running card above the wall. `current` may
    /// still name the picture the last run left behind, and ringing that one would point at the
    /// wrong place.
    private func isShowing(_ tile: TimelineTile) -> Bool {
        guard !store.isShowingRun else { return false }
        guard let file = tile.fileURL, let current = store.current?.fileURL else { return false }
        return current.standardizedFileURL == file.standardizedFileURL
    }
}

#Preview("A batch on top of some singles") {
    let run = PreviewImages.run(of: 2)
    let singles = PreviewImages.library(count: 5).items
    List {
        TimelineTileGrid(
            tiles: run.map { .fresh($0) } + [.pending(2), .pending(3)] + singles.map { .item($0) })
        .listRowBackground(Color.clear)
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 360)
    .environment(ImageCache())
    .environment(ThumbnailCache())
    .environment(GenerationStore.preview(state: .ready, images: run))
}

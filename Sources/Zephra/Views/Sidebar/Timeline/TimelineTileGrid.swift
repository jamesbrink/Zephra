import SwiftUI
import ZephraEngine

/// Today's pictures as a wall of small squares, newest run first, with a dashed place for each
/// seed still to come at the top of it.
///
/// One wall for the whole day rather than a grid per run. A run of one picture in a grid of its
/// own left two thirds of the row empty and put a caption over every single square; here the
/// singles pack three across, and what any of them was asked for is in the inspector or under
/// the pointer as a tooltip. A batch still reads as a batch: `SessionTimeline.blocks(of:)`
/// gives the running run and any run of several squares a block of its own, and the blocks
/// stack with a gutter and nothing else between them.
///
/// One list row rather than a row per tile, because the wall is a single object to scroll past
/// and a `List` that thought it held forty rows would put separators through it.
struct TimelineTileGrid: View {
    /// The wall, cut into blocks.
    let blocks: [TimelineBlock]

    @Environment(GenerationStore.self) private var store
    @Environment(ThumbnailCache.self) private var thumbnails

    /// Three across at the sidebar's usual width; four when it is dragged wide.
    private static let columns = [GridItem(.adaptive(minimum: 72), spacing: 4)]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(blocks) { block in
                LazyVGrid(columns: Self.columns, spacing: 4) {
                    ForEach(block.tiles) { tile in
                        WallSquare(tile: tile, isShowing: isShowing(tile))
                    }
                }
            }
        }
        .environment(\.libraryThumbnails, LibraryThumbnails(cache: thumbnails, size: .small))
        .padding(.vertical, 2)
    }

    /// Whether this is the picture the canvas is showing, so the sidebar and the canvas agree
    /// about where you are.
    private func isShowing(_ tile: TimelineTile) -> Bool {
        guard let file = tile.fileURL, let current = store.current?.fileURL else { return false }
        return current.standardizedFileURL == file.standardizedFileURL
    }
}

#Preview("A batch on top of some singles") {
    let run = PreviewImages.run(of: 2)
    let singles = PreviewImages.library(count: 5).items
    List {
        TimelineTileGrid(blocks: [
            TimelineBlock(id: UUID(), tiles: run.map { .fresh($0) } + [.pending(2), .pending(3)]),
            TimelineBlock(id: UUID(), tiles: singles.map { .item($0) }),
        ])
        .listRowBackground(Color.clear)
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 360)
    .environment(ImageCache())
    .environment(ThumbnailCache())
    .environment(GenerationStore.preview(state: .ready, images: run))
}

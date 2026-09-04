import SwiftUI
import ZephraEngine

/// One square of a run: a picture the library knows about, a picture this session has just
/// made, or the place one is still to take.
///
/// The three draw the same size and sit in the same cell, which is the whole point of the
/// timeline's tile: a run's row is laid out once and then filled in, rather than growing a
/// square at a time as the seeds land.
///
/// An indexed picture opens on the canvas without adopting its settings, through the same
/// `openLibraryItem` action the library grid and the inspector use, and wears the same
/// `LibraryItemMenu` the grid does — every image in the app is meant to, and `LibraryItemMenu`
/// takes no selection to move when there is none, which is the sidebar's case.
struct RunTile: View {
    /// What this square stands for.
    let tile: TimelineTile

    @Environment(\.openLibraryItem) private var open

    var body: some View {
        switch tile {
        case .item(let item):
            Button { open(item) } label: {
                LibraryThumbnail(item: item)
                    .overlay(alignment: .topLeading) {
                        if let upscale = item.upscale { UpscaleBadge(factor: upscale.factor) }
                    }
            }
            .buttonStyle(.plain)
            .help(item.prompt.isEmpty ? item.fileName : item.prompt)
            .accessibilityLabel(item.prompt.isEmpty ? item.fileName : item.prompt)
            .contextMenu { LibraryItemMenu(items: [item]) }
        case .fresh(let image):
            FilmstripThumbnail(image: image)
        case .pending:
            PendingThumbnail()
        }
    }
}

#Preview("The three tiles") {
    HStack(spacing: 6) {
        RunTile(tile: .item(PreviewImages.library(count: 1).items[0]))
        RunTile(tile: .fresh(PreviewImages.sample()))
        RunTile(tile: .pending(2))
    }
    .frame(width: 240)
    .padding()
    .environment(ImageCache())
    .environment(GenerationStore.preview(state: .ready))
}

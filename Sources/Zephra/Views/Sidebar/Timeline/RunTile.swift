import SwiftUI
import ZephraEngine
import ZephraStyle

/// One square of a run: a picture the library knows about, or a picture this session has just
/// made.
///
/// The two draw the same size and sit in the same cell, so a run's squares read as one run
/// whether the file has been indexed yet or not.
///
/// A square is a run to pick up again, whichever kind it is: an indexed picture goes onto the
/// canvas *with* its settings through `GenerationStore.select(_:)`, the way a fresh one does
/// through `FilmstripThumbnail`, so the prompt, the size and the seed land in the capsule and
/// the running card puts the run's own back. That is the one place a click on a picture adopts
/// its settings without being asked; the library grid's "Open in Canvas" only looks. Every
/// square wears the same `LibraryItemMenu` the grid does — every image in the app is meant to,
/// and `LibraryItemMenu` takes no selection to move when there is none, which is the sidebar's
/// case.
struct RunTile: View {
    /// What this square stands for.
    let tile: TimelineTile

    @Environment(GenerationStore.self) private var store

    var body: some View {
        switch tile {
        case .item(let item):
            Button { Task { await store.select(item) } } label: {
                LibraryThumbnail(item: item)
                    .overlay(alignment: .topLeading) {
                        if let upscale = item.upscale {
                            UpscaleBadge(factor: upscale.factor)
                        } else if let seconds = item.videoSeconds {
                            VideoBadge(seconds: seconds)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help(item.prompt.isEmpty ? item.fileName : item.prompt)
            .accessibilityLabel(item.prompt.isEmpty ? item.fileName : item.prompt)
            .contextMenu { LibraryItemMenu(items: [item]) }
        case .fresh(let image):
            FilmstripThumbnail(image: image)
        }
    }
}

#Preview("The two tiles") {
    HStack(spacing: 6) {
        RunTile(tile: .item(PreviewImages.library(count: 1).items[0]))
        RunTile(tile: .fresh(PreviewImages.sample()))
    }
    .frame(width: 240)
    .padding()
    .environment(ImageCache())
    .environment(GenerationStore.preview(state: .ready))
}

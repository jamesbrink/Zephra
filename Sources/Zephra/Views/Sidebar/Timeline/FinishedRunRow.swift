import SwiftUI
import ZephraEngine

/// A run that is over: one quiet line of what was asked for, and the pictures it produced.
///
/// No card and no chrome. A finished run is something to look at, not something happening, and
/// a column of bordered panels would make the whole sidebar read as work in progress.
struct FinishedRunRow: View {
    /// The run that is over.
    let run: TimelineRun

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(run.prompt)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
            RunTileGrid(tiles: run.tiles)
        }
    }
}

#Preview("A finished run") {
    let made = PreviewImages.run(of: 3)
    List {
        ForEach(
            SessionTimeline.build(
                items: [], history: made, queue: [], running: nil,
                isToday: Calendar.current.isDateInToday)
        ) { run in
            FinishedRunRow(run: run)
                .listRowBackground(Color.clear)
        }
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 300)
    .environment(ImageCache())
    .environment(ThumbnailCache())
    .environment(GenerationStore.preview(state: .ready, images: made))
}

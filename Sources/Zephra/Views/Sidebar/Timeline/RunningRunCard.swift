import SwiftUI
import ZephraCore
import ZephraEngine

/// The run being rendered right now, in safelight amber with the same step segments that ride
/// the top of the prompt capsule. It is the only amber thing in the sidebar, because amber
/// means the model is working and nothing else in there is.
///
/// The run's own seeds are the first squares of the wall right under it — the ones already
/// made, then a dashed place for each still to come — so the card says how far along the
/// model is and the wall says what has come out.
///
/// It is a button, and pressing it puts the canvas back on the run. That is the way back from
/// having opened an earlier picture while the model works: the card is the run, so the run is
/// what it shows you. It wears the accent ring the wall's squares wear when the canvas is
/// already showing it, so "where am I" has one answer in one place. The frame at its leading
/// edge is the newest one the run has sent, which is what makes the card worth glancing at
/// while you are looking at something else.
struct RunningRunCard: View {
    /// The run in flight.
    let run: TimelineRun

    @Environment(GenerationStore.self) private var store

    var body: some View {
        Button { store.watchRun() } label: { card }
            .buttonStyle(.plain)
            .help(store.isShowingRun ? "Showing on the canvas" : "Show this run on the canvas")
            .accessibilityLabel("Generating: \(run.prompt)")
            .accessibilityAddTraits(store.isShowingRun ? .isSelected : [])
    }

    private var card: some View {
        HStack(spacing: 9) {
            RunPreviewThumbnail()
            VStack(alignment: .leading, spacing: 7) {
                Text(run.prompt)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                StepSegments(progress: store.stepProgress)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .chromePanel(.warning)
        .overlay {
            if store.isShowingRun {
                RoundedRectangle(cornerRadius: ZephraChrome.cardRadius + 1, style: .continuous)
                    .inset(by: -1)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
    }
}

#Preview("Running, and shown on the canvas") {
    let running = InterfacePreview.queuedRun(of: 3)
    List {
        ForEach(
            SessionTimeline.build(
                items: [], history: [], queue: Array(running.dropFirst()), running: running[0],
                isToday: Calendar.current.isDateInToday)
        ) { run in
            RunningRunCard(run: run)
                .listRowBackground(Color.clear)
        }
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 300)
    .environment(ImageCache())
    .environment(ThumbnailCache())
    .environment(GenerationStore.preview(
        state: .generating(GenerationProgressEvent(
            phase: .denoising(step: 3, of: 4),
            fraction: 0.75,
            secondsPerStep: 8.2
        )),
        running: running[0],
        queue: Array(running.dropFirst()),
        livePreview: PreviewImages.frame()
    ))
}

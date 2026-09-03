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
struct RunningRunCard: View {
    /// The run in flight.
    let run: TimelineRun

    @Environment(GenerationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(run.prompt)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
            StepSegments(
                total: store.running?.settings.steps ?? 0,
                completed: store.state.denoisingProgress?.step ?? 0,
                isRunning: store.state.denoisingProgress != nil
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .chromePanel(.warning)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Running") {
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
        queue: Array(running.dropFirst())
    ))
}

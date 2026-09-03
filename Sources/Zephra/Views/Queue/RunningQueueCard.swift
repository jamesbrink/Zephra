import SwiftUI
import ZephraCore
import ZephraEngine

/// The seed being rendered right now, in safelight amber with the same step segments that ride
/// the top of the prompt capsule. It is the only amber thing in the sidebar, because amber
/// means the model is working and nothing else in there is.
struct RunningQueueCard: View {
    /// The generation in flight.
    let item: QueuedGeneration

    @Environment(GenerationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.settings.prompt)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
            StepSegments(
                total: item.settings.steps,
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
    RunningQueueCard(item: QueuedGeneration(
        model: ModelCatalog.default,
        settings: GenerationSettings(
            prompt: "a red bicycle against a limestone wall",
            size: ImageSize(width: 1024, height: 1024),
            steps: 4,
            guidance: 0,
            seed: 42
        )
    ))
    .padding()
    .frame(width: 280)
    .environment(GenerationStore.preview(state: .generating(GenerationProgressEvent(
        phase: .denoising(step: 3, of: 4),
        fraction: 0.75,
        secondsPerStep: 8.2
    ))))
}

import SwiftUI

/// What the model is doing once its steps are done, with the system's spinner, floating at
/// the top edge of the run's frame.
///
/// The last step's frame stays on the canvas while the latents are decoded and, for a clip,
/// the frames encoded; on a 121-frame clip that is tens of seconds with nothing moving and the
/// step bar full, which read as finished. The spinner is the system's indeterminate indicator,
/// the one moving thing this canvas allows while the model works (`RunPlaceholderView`). The
/// note shows only after the phase has lasted a moment, so a picture model's half-second
/// decode does not flash a panel in front of the picture.
struct FinishingNote: View {
    /// What the model is doing, from `GenerationStore.finishingPhase`.
    let phase: String
    @State private var shown = false

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.safelight)
            Text(phase)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .chromePanel(.floating)
        .opacity(shown ? 1 : 0)
        .accessibilityHidden(!shown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase)
        .task {
            try? await Task.sleep(for: .seconds(1))
            shown = true
        }
    }
}

#Preview("Developing a clip") {
    FinishingNote(phase: "Developing the clip")
        .padding(40)
        .background(Color.canvasBackground)
}

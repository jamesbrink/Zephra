import SwiftUI

/// The run's own rectangle before its first frame: a card that breathes, an amber spinner, and
/// a word for what the model is doing.
///
/// A run's first frame comes only after its first step, which on a large model is half a
/// minute, and an empty rectangle for that long reads as nothing happening. Bare step
/// segments in the middle of it read as a second progress bar, when the capsule's edge and the
/// toolbar already carry one. So this says what the wait is rather than how far it has got:
/// the phase in words, and a hint that a picture follows the first step. Safelight amber is
/// the colour of "only while the model works", which is exactly when this is on screen.
struct RunPlaceholderView: View {
    /// What the model is doing, from `EngineState.generationPhase`, or nil between phases.
    let phase: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ZephraChrome.cardRadius)
                .fill(Color.safelight.opacity(breathing ? 0.07 : 0.03))
                .strokeBorder(ZephraChrome.hairline, lineWidth: 1)
                .padding(1)
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.safelight)
                Text(phase ?? "Starting")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("A preview appears after the first step.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .multilineTextAlignment(.center)
            .padding(24)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase ?? "Starting")
    }
}

#Preview("Waiting for the first frame") {
    RunPlaceholderView(phase: "Step 1 of 4")
        .aspectRatio(1, contentMode: .fit)
        .padding(40)
        .frame(width: 520, height: 520)
        .background(Color.canvasBackground)
}

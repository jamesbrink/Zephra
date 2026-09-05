import SwiftUI

/// The run's own rectangle before its first frame: a still safelight card, the system's
/// spinner, and a word for what the model is doing.
///
/// A run's first frame comes only after its first step, which on a large model is half a
/// minute, and an empty rectangle for that long reads as nothing happening. Bare step
/// segments in the middle of it read as a second progress bar, when the capsule's edge and the
/// toolbar already carry one. So this says what the wait is rather than how far it has got:
/// the phase in words, and a hint that a picture follows the first step. Safelight amber is
/// the colour of "only while the model works", which is exactly when this is on screen.
///
/// The card is deliberately still. It once breathed, a repeating opacity animation across
/// the whole rectangle, and on a 16 GB M4 mini that took the GPU down: sixty frames a second
/// of compositing over a streamed Qwen-Image step ended, every time, in a GPU restart that
/// MLX reports as an uncaught exception, and the app aborted a step in. With the animation off
/// the same step ran to a picture. The spinner is the system's own indeterminate indicator,
/// which that run kept on screen throughout; the rule is in `make lint-layers`.
struct RunPlaceholderView: View {
    /// What the model is doing, from `EngineState.generationPhase`, or nil between phases.
    let phase: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ZephraChrome.cardRadius)
                .fill(Color.safelight.opacity(0.05))
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

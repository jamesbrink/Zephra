import SwiftUI
import ZephraStyle

/// The run's own rectangle before its first frame: a still safelight card, the system's
/// spinner, and a word for what the Mac is doing.
///
/// A run's first frame comes only after its first step, which on a large model is half a
/// minute, and an empty rectangle for that long reads as nothing happening. The phase is the
/// Mac's own word for it — "Denoising", "Decoding", "Saving" — so the two ends can never
/// disagree about what is happening.
///
/// Still, like the Mac's view of the same name. A repeating animation over a streamed step
/// took a 16 GB M4 mini's GPU down, and the ban is enforced by `make lint-layers` on both app
/// targets; the spinner is the system's own indeterminate indicator, which that run kept on
/// screen throughout.
struct RunPlaceholderView: View {
    /// What the Mac is doing, or nil between phases.
    let phase: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous)
                .fill(ZephraChrome.safelightWash)
                .strokeBorder(ZephraChrome.hairline, lineWidth: 1)
            VStack(spacing: 10) {
                ProgressView()
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
    RunPlaceholderView(phase: "Denoising")
        .aspectRatio(1, contentMode: .fit)
        .padding(40)
        .background(Color.canvasBackground)
}

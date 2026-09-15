import SwiftUI
import ZephraStyle

/// The run's own rectangle after a run was lost: the Mac's sentence, and the way back.
///
/// The Mac's words, never the phone's. A GPU fault, a model that would not fit and a download
/// that failed are three different sentences the Mac has already written for the person at its
/// keyboard, and a second rendering of them here could only be a worse one.
///
/// Still, like `RunPlaceholderView` beside it and for the same reason: no repeating animation
/// runs in either app target. Neutral, unlike it: safelight amber means "only while the model
/// works" and appears nowhere else, and a run that is over is the one thing this card is about.
/// The Mac's failed state is a plain floating panel for the same reason. The glyph is the whole
/// of the signal.
struct RunFailureView: View {
    /// What went wrong, in the Mac's own words.
    let message: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous)
                .fill(ZephraChrome.wellFill)
                .strokeBorder(ZephraChrome.hairline, lineWidth: 1)
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(message ?? "That run was lost.")
                    .font(.callout)
                    .foregroundStyle(.primary)
                TryAgainButton()
            }
            .multilineTextAlignment(.center)
            .padding(24)
        }
    }
}

#Preview("A run that was lost") {
    RunFailureView(message: "The GPU stopped responding and this run was lost. Try again.")
        .aspectRatio(1, contentMode: .fit)
        .padding(40)
        .background(Color.canvasBackground)
        .environment(MobilePreview.unpairedClient())
}

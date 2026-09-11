import SwiftUI

/// Swipe down to close, the way Photos closes.
///
/// The finger is read by the page's own pan recognizer (`ZoomingScrollView+Pull`) and arrives
/// here as `ViewerGestures.PullPhase`; this is what the pull does to the screen. The picture
/// drops by the offset, shrinks a little, and the black behind it thins so the grid shows
/// through. Letting go past `MobileChrome.viewerDismissDistance`, or flinging it, closes the
/// viewer; short of that it springs back, or snaps back under Reduce Motion.
///
/// Off while the picture is zoomed, twice over: the recognizer refuses to begin, and a phase
/// that arrives regardless is ignored.
struct ViewerPull: ViewModifier {
    /// How far the picture has come, and whose the drag is.
    @Binding var pull: ViewerPose.Pull
    /// Whether a pull may move anything.
    let isEnabled: Bool

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        ZStack {
            Color.black.opacity(1 - pull.progress).ignoresSafeArea()
            content
                .scaleEffect(1 - 0.25 * pull.progress)
                .offset(y: pull.offset)
        }
        .transformEnvironment(\.viewerGestures) { $0.pulled = follow }
    }

    /// One phase of the pull: follow the finger, or decide what letting go means.
    private func follow(_ phase: ViewerGestures.PullPhase) {
        guard isEnabled else { return }
        switch phase {
        case .changed(let translation):
            pull.follow(translation)
        case .ended(let translation, let velocity):
            pull.follow(translation)
            let closes = pull.axis == .vertical
                && ViewerPose.Pull.shouldDismiss(
                    offset: pull.offset,
                    predicted: ViewerPose.Pull.predictedEnd(offset: pull.offset, velocity: velocity))
            if closes {
                dismiss()
            } else {
                withAnimation(motion) { pull.release() }
            }
        }
    }

    /// The spring back, or none at all where somebody has asked for less movement.
    private var motion: Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .spring(duration: 0.3)
    }
}

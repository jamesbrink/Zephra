import SwiftUI

/// Swipe down to close, the way Photos closes.
///
/// A drag over the pager that reads the finger beside the pager's own pan rather than instead
/// of it. `ViewerPose.Pull` locks the axis on the first movement, so a sideways drag is the
/// pager's and this does nothing, and a downward one carries the picture with it: it drops by
/// the offset, shrinks a little, and the black behind it thins so the grid shows through.
/// Letting go past `MobileChrome.viewerDismissDistance`, or flinging it, closes the viewer;
/// short of that it springs back, or snaps back under Reduce Motion.
///
/// Off while the picture is zoomed: a drag then is a pan of the picture, and the scroll view
/// underneath has it.
struct ViewerPull: ViewModifier {
    /// How far the picture has come, and whose the drag is.
    @Binding var pull: ViewerPose.Pull
    /// Whether a drag may pull at all.
    let isEnabled: Bool

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        ZStack {
            Color.black.opacity(1 - pull.progress).ignoresSafeArea()
            content
                .scaleEffect(1 - 0.25 * pull.progress)
                .offset(y: pull.offset)
        }
        .simultaneousGesture(drag, isEnabled: isEnabled)
    }

    /// The drag itself. Twelve points before it starts, so a tap stays a tap.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { pull.follow($0.translation) }
            .onEnded { value in
                let closes = pull.axis == .vertical
                    && ViewerPose.Pull.shouldDismiss(
                        offset: pull.offset, predicted: value.predictedEndTranslation.height)
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

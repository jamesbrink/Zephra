import UIKit

/// The pull downwards that closes the viewer, read where the other gestures are read.
///
/// A pan recognizer on the page rather than a SwiftUI drag over the pager, because the two
/// scroll views underneath claim every touch before a SwiftUI gesture sees one. It begins for
/// any touch at fit, since UIKit asks before the finger has moved (a touch held still on a
/// scroll view is asked at zero translation), and decides on the first change that has gone
/// `pullDecision` points: downwards is a pull, anything else cancels the recognizer, which is
/// the failure the pager's pan has been told to wait for. So a sideways drag is the pager's,
/// a drag on a zoomed picture is the picture's, and a pull never drags the next picture a few
/// points sideways on its way down.
extension ZoomingScrollView: UIGestureRecognizerDelegate {
    /// How far a finger goes before its direction is read. Under the pager's own threshold,
    /// so the pager is never kept waiting past where it would have begun on its own.
    static let pullDecision: CGFloat = 8

    /// Puts the recognizer on the page. Called once, from `init`.
    func configurePull() {
        pullRecognizer.maximumNumberOfTouches = 1
        pullRecognizer.delegate = self
        pullRecognizer.addTarget(self, action: #selector(pulled))
        addGestureRecognizer(pullRecognizer)
    }

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer === pullRecognizer else {
            return super.gestureRecognizerShouldBegin(recognizer)
        }
        return zoomScale <= 1.001
    }

    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        recognizer === pullRecognizer || other === pullRecognizer
    }

    /// The pager's pan, and any other scroll view's, waits for the pull to decide.
    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        recognizer === pullRecognizer && other is UIPanGestureRecognizer
            && other.view !== self && other.view is UIScrollView
    }

    @objc private func pulled(_ pan: UIPanGestureRecognizer) {
        let point = pan.translation(in: self)
        let translation = CGSize(width: point.x, height: point.y)
        switch pan.state {
        case .began:
            isPulling = false
        case .changed:
            if !isPulling {
                let moved = max(abs(translation.width), abs(translation.height))
                guard moved >= Self.pullDecision else { return }
                guard ViewerPose.Pull.axis(for: translation) == .vertical, translation.height > 0
                else {
                    // Not a pull: cancelling is what lets the pager begin on this touch.
                    pan.isEnabled = false
                    pan.isEnabled = true
                    return
                }
                isPulling = true
            }
            onPull(.changed(translation))
        case .ended, .cancelled, .failed:
            guard isPulling else { return }
            isPulling = false
            onPull(.ended(translation, velocity: pan.velocity(in: self).y))
        default:
            break
        }
    }
}

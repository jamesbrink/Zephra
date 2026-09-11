import UIKit

/// The pull downwards that closes the viewer, read where the other gestures are read.
///
/// A pan recognizer on the page rather than a SwiftUI drag over the pager, because the scroll
/// views underneath claim every touch before a SwiftUI gesture sees one. One recognizer for
/// both kinds of page: a picture's `ZoomingScrollView` and a clip's player view attach the
/// same one, so a clip drops and closes exactly as a picture does.
///
/// It begins for any touch `mayBegin` allows — a picture at fit, a clip always — since UIKit
/// asks before the finger has moved (a touch held still on a scroll view is asked at zero
/// translation, and a refusal there is final), and decides on the first change that has gone
/// `decision` points: downwards is a pull, anything else cancels the recognizer, which is the
/// failure the pager's pan has been told to wait for. So a sideways drag is the pager's, a
/// drag on a zoomed picture is the picture's, and a pull never drags the next picture a few
/// points sideways on its way down.
///
/// It is its own delegate, recognizes beside every other recognizer and cancels no touch in
/// the view under it, which is what keeps AVKit's taps and its scrubber working under a clip.
final class ViewerPullRecognizer: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    /// What a pull does, phase by phase.
    var onPull: (ViewerGestures.PullPhase) -> Void = { _ in }
    /// Whether a touch may start a pull at all. A picture answers "at fit"; a clip, always.
    var mayBegin: () -> Bool = { true }

    /// How far a finger goes before its direction is read. Under the pager's own threshold,
    /// so the pager is never kept waiting past where it would have begun on its own.
    static let decision: CGFloat = 8

    /// Whether the touch in flight has been read as a pull downwards.
    private var isPulling = false

    init() {
        super.init(target: nil, action: nil)
        maximumNumberOfTouches = 1
        cancelsTouchesInView = false
        delegate = self
        addTarget(self, action: #selector(pulled))
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        mayBegin()
    }

    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }

    /// The pager's pan, and any other scroll view's around the page, waits for the pull to
    /// decide. The page's own scroll view is not made to wait: at fit it has nothing to scroll.
    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        other is UIPanGestureRecognizer && other.view !== view && other.view is UIScrollView
    }

    @objc private func pulled(_ pan: UIPanGestureRecognizer) {
        let point = pan.translation(in: view)
        let translation = CGSize(width: point.x, height: point.y)
        switch pan.state {
        case .began:
            isPulling = false
        case .changed:
            if !isPulling {
                let moved = max(abs(translation.width), abs(translation.height))
                guard moved >= Self.decision else { return }
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
            onPull(.ended(translation, velocity: pan.velocity(in: view).y))
        default:
            break
        }
    }
}

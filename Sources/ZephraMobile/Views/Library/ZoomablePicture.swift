import SwiftUI
import UIKit

/// One picture, pinched and double-tapped to zoom, dragged around once it is zoomed.
///
/// A `ZoomingScrollView` wrapped for SwiftUI rather than a SwiftUI gesture, because the pager
/// around it is a scroll view too and UIKit already knows how two nested ones share a finger:
/// at fit the inner one has nothing to scroll and the pan is the pager's, zoomed in it is the
/// picture's. A `DragGesture` over the same pixels had to guess, and guessed wrong.
///
/// What the fingers do goes up through `\.viewerGestures`; whether this page is the one on
/// screen comes down through `\.viewerPageIsCurrent`, and a page that stops being it goes
/// back to fit, so swiping away from a zoomed picture and back finds it as Photos would.
struct ZoomablePicture: UIViewRepresentable {
    /// The picture, decoded already: `ViewerPicture` does that off the main actor, since a
    /// whole picture off a Mac is megabytes and decoding one here would freeze the pinch.
    let picture: UIImage

    @Environment(\.viewerGestures) private var gestures
    @Environment(\.viewerPageIsCurrent) private var isCurrent

    func makeUIView(context: Context) -> ZoomingScrollView {
        let view = ZoomingScrollView()
        view.image = picture
        return view
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        // Set on every update, not once: the closures close over the viewer's state and a
        // stale pair would toggle the chrome of a viewer that has since been rebuilt.
        view.onTap = gestures.tapped
        view.onZoom = gestures.zoomed
        view.pull.onPull = gestures.pulled
        if view.image !== picture { view.image = picture }
        if !isCurrent { view.resetZoom() }
    }
}

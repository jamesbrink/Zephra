import AppKit
import Observation

/// One zoomable picture as the menu bar sees it: where it is zoomed to, what it allows, and the
/// four presses `ZoomCommands` makes on it.
///
/// `ZoomablePicture` owns one and publishes it as the scene's `pictureZoom` for as long as it
/// is on screen; `ZoomScrollView` writes `magnification` and `scale` whenever either moves —
/// a pinch, a resize, a new picture — so a greyed menu item is always the scroll view's own
/// answer rather than a second idea of it. The presses go back through the same view, which
/// holds the scroll view weakly: the view is AppKit's, and outlives nothing.
@MainActor
@Observable
final class PictureZoom {
    /// The current magnification, 1 being the picture fitted to its pane.
    private(set) var magnification: CGFloat = 1
    /// What the picture on screen allows.
    private(set) var scale = ZoomScale(pixels: .zero, fitted: .zero)

    @ObservationIgnored weak var view: ZoomScrollView?

    /// Whether Zoom In has anywhere to go.
    var canZoomIn: Bool { view != nil && scale.zoomIn(from: magnification) != nil }
    /// Whether Zoom Out has anywhere to go.
    var canZoomOut: Bool { view != nil && scale.zoomOut(from: magnification) != nil }
    /// Whether Actual Size would change anything.
    var canShowActualSize: Bool { view != nil && !scale.isActualSize(magnification) }
    /// Whether Zoom to Fit would change anything.
    var canFit: Bool { view != nil && !scale.isFit(magnification) }

    /// The next stop in, about the middle of what is on screen.
    func zoomIn() { scale.zoomIn(from: magnification).map(apply) }
    /// The next stop out.
    func zoomOut() { scale.zoomOut(from: magnification).map(apply) }
    /// One picture pixel to one point.
    func showActualSize() { apply(scale.actualSize) }
    /// The whole picture in its pane.
    func fit() { apply(1) }

    /// What the scroll view reports after anything moved.
    func report(magnification: CGFloat, scale: ZoomScale) {
        if self.magnification != magnification { self.magnification = magnification }
        if self.scale != scale { self.scale = scale }
    }

    private func apply(_ magnification: CGFloat) {
        view?.zoom(to: magnification)
    }
}

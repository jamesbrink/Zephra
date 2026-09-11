import SwiftUI

/// What a picture in the viewer tells the viewer about the fingers on it.
///
/// The zoom is a `UIScrollView` inside a SwiftUI pager, and a scroll view cannot reach the
/// pose that decides whether the chrome is up or how far the picture has been pulled. So the
/// facts it has go up as closures in the environment, the way a cell's menu asks for a sheet
/// through `LibraryActions`: the pager fills them in once, every page reads them, and a page
/// on its own in a preview gets the defaults, which do nothing.
///
/// The pull is read in UIKit as well, not by a SwiftUI `DragGesture` over the pager: the
/// scroll views underneath claim every touch before SwiftUI's gesture sees one, so a drag
/// read there fired for nothing. A pan recognizer on the page is a peer of theirs.
struct ViewerGestures {
    /// A single tap landed on the picture, which is "hide the chrome" or "show it".
    var tapped: () -> Void = {}
    /// The picture went in past fit, or came back to it.
    var zoomed: (Bool) -> Void = { _ in }
    /// The picture is being pulled down, or has been let go.
    var pulled: (PullPhase) -> Void = { _ in }

    /// One moment of a pull: where the finger has taken the picture, or where it let go.
    enum PullPhase {
        /// The finger moved; the translation is from where the drag began.
        case changed(CGSize)
        /// The finger lifted, at this translation, moving this fast downwards in points a
        /// second (negative for upwards).
        case ended(CGSize, velocity: CGFloat)
    }
}

extension EnvironmentValues {
    /// The viewer's answers to a tap, a zoom and a pull, for the picture under the finger.
    @Entry var viewerGestures = ViewerGestures()
    /// Whether the page reading this is the one on screen. A page that stops being it puts
    /// its zoom back to fit, so swiping away from a zoomed picture and back finds it fitted,
    /// which is what Photos does.
    @Entry var viewerPageIsCurrent = true
}

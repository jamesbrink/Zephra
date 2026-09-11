import SwiftUI

/// What a picture in the viewer tells the viewer about the fingers on it.
///
/// The zoom is a `UIScrollView` inside a SwiftUI pager, and a scroll view cannot reach the
/// pose that decides whether the chrome is up or the pull-down is armed. So the two facts it
/// has go up as closures in the environment, the way a cell's menu asks for a sheet through
/// `LibraryActions`: the pager fills them in once, every page reads them, and a page on its
/// own in a preview gets the defaults, which do nothing.
struct ViewerGestures {
    /// A single tap landed on the picture, which is "hide the chrome" or "show it".
    var tapped: () -> Void = {}
    /// The picture went in past fit, or came back to it.
    var zoomed: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    /// The viewer's answers to a tap and a zoom, for the picture under the finger.
    @Entry var viewerGestures = ViewerGestures()
    /// Whether the page reading this is the one on screen. A page that stops being it puts
    /// its zoom back to fit, so swiping away from a zoomed picture and back finds it fitted,
    /// which is what Photos does.
    @Entry var viewerPageIsCurrent = true
}

import SwiftUI

/// The rectangle a picture of `aspect` takes fitted in whatever rectangle it is handed.
///
/// `ZoomablePicture` fills its pane, so a zoomed picture can use all of it, but at fit the
/// gestures laid on it — the tuck, the menu, the drag — belong to the picture and not to the
/// graphite letterbox either side of it, which is what they answered before the picture could
/// zoom. This is that picture's content shape at fit. Zoomed in, the picture is the whole pane
/// — what was letterbox at fit is picture now, or about to be one pan away — so `fills` hands
/// back the whole rectangle and a right click or a drag-out anywhere in it is the picture's.
struct AspectFitShape: Shape {
    /// Width over height.
    let aspect: CGFloat
    /// Whether the whole rectangle is the shape, which is so while the picture is zoomed in.
    var fills = false

    func path(in rect: CGRect) -> Path {
        if fills { return Path(rect) }
        let size = ZoomScale.fitted(aspect: aspect, in: rect.size)
        return Path(CGRect(
            x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
            width: size.width, height: size.height))
    }
}

import AppKit
import SwiftUI

/// `ZoomScrollView` in SwiftUI. Everything it holds is handed in; the zoom itself lives in the
/// scroll view, which is AppKit's and survives every `body`.
struct ZoomScrollRepresentable: NSViewRepresentable {
    /// The pixels and whether they carry alpha.
    let picture: DrawnPicture
    /// What resets the zoom to fit when it changes.
    let key: AnyHashable
    /// What the menu bar reads and presses.
    let zoom: PictureZoom

    func makeNSView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView(frame: .zero)
        view.zoom = zoom
        return view
    }

    func updateNSView(_ view: ZoomScrollView, context: Context) {
        if view.zoom !== zoom { view.zoom = zoom }
        view.show(picture.image, hasAlpha: picture.hasAlpha, key: key)
    }
}

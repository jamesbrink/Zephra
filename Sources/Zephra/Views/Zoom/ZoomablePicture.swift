import SwiftUI

/// A still picture that pinches, pans and answers View > Zoom In, Zoom Out, Actual Size and
/// Zoom to Fit — the canvas's and the library viewer's, and nothing else's. Clips, the live
/// preview, thumbnails and the inspector stay plain pictures.
///
/// It fills what it is given, so a zoomed picture has the whole pane, and at fit it answers
/// hit-testing only over the picture itself (`AspectFitShape`), so the gestures its callers lay
/// on it act where they always did. `key` is what puts it back at fit: a new picture on the
/// canvas, a step in the viewer.
///
/// The zoom state is `ZoomScrollView`'s, AppKit's own, and the menu bar reaches it through the
/// `PictureZoom` this view publishes as the scene's `pictureZoom` while it is on screen. The
/// canvas and the library pane are never up at once, so there is only ever one.
struct ZoomablePicture: View {
    /// The pixels and whether they carry alpha.
    let picture: DrawnPicture
    /// What resets the zoom to fit when it changes.
    let key: AnyHashable

    @State private var zoom = PictureZoom()

    var body: some View {
        ZoomScrollRepresentable(picture: picture, key: key, zoom: zoom)
            .contentShape(AspectFitShape(aspect: aspect))
            .focusedSceneValue(\.pictureZoom, zoom)
    }

    private var aspect: CGFloat {
        let pixels = picture.image.pixelSize
        return pixels.height > 0 ? pixels.width / pixels.height : 1
    }
}

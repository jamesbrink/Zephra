import SwiftUI

extension FocusedValues {
    /// The zoomable picture on screen — the canvas's still or the library viewer's — for as long
    /// as it is up, and nil otherwise, which is what greys View > Actual Size and Zoom to Fit
    /// and hands ⌘+ and ⌘− back to the library's thumbnails.
    ///
    /// A scene value rather than a view one: the zoom is about what the window shows, not about
    /// where the typing goes, so ⌘+ zooms the canvas's picture while the prompt has the keyboard
    /// as Preview's does while its search field has it.
    @Entry var pictureZoom: PictureZoom?
}

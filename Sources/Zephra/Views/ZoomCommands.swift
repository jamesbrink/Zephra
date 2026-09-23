import SwiftUI

/// View > Zoom In (⌘+), Zoom Out (⌘−), Actual Size (⌘0) and Zoom to Fit (⌘9), the chords
/// Preview and every other Mac viewer use for them.
///
/// **One owner for ⌘+ and ⌘−.** They zoom the picture on screen — the canvas's still, the
/// library viewer's — while there is one (`pictureZoom`), and step the library's thumbnails
/// (`ThumbnailSizeSteps`) while the grid is up instead. Two menu items declaring the same chord
/// would leave which one fires to AppKit, so the one item decides. Actual Size and Zoom to Fit
/// have nothing to mean for a grid and are grey with no picture up.
struct ZoomCommands: Commands {
    @FocusedValue(\.pictureZoom) private var zoom
    @FocusedValue(\.librarySelection) private var selection

    @AppStorage(AppSettings.libraryThumbnailEdge)
    private var edge = AppSettings.initialLibraryThumbnailEdge

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!canZoomIn)
            Button("Zoom Out") { zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!canZoomOut)
            Button("Actual Size") { zoom?.showActualSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(zoom?.canShowActualSize != true)
            Button("Zoom to Fit") { zoom?.fit() }
                .keyboardShortcut("9", modifiers: .command)
                .disabled(zoom?.canFit != true)
            Divider()
        }
    }

    private var canZoomIn: Bool {
        if let zoom { return zoom.canZoomIn }
        return selection != nil && ThumbnailSizeSteps.bigger(than: edge) != nil
    }

    private var canZoomOut: Bool {
        if let zoom { return zoom.canZoomOut }
        return selection != nil && ThumbnailSizeSteps.smaller(than: edge) != nil
    }

    private func zoomIn() {
        if let zoom { zoom.zoomIn() } else { edge = ThumbnailSizeSteps.bigger(than: edge) ?? edge }
    }

    private func zoomOut() {
        if let zoom { zoom.zoomOut() } else { edge = ThumbnailSizeSteps.smaller(than: edge) ?? edge }
    }
}

import SwiftUI

/// The viewer over a surface, opened out of a cell and closed back into one.
///
/// Both surfaces with pictures on them present the viewer the same way, so this is the one
/// place the presentation is decided: a full-screen cover over a clear background, so the
/// grid shows through a pull, and the system's zoom transition out of the cell that was
/// tapped and back into the cell the viewer is on when it closes.
///
/// That last part is the catch. The zoom's source id is fixed when the cover goes up, and
/// Photos closes a picture into the cell it is *now* over, not the one it opened on. So the
/// cover's item is a `ViewerOpening` — the picture opened on, which is its identity so paging
/// never re-presents, and the one shown, which the viewer reports through `\.viewerPaged` —
/// and every cell reads it from the environment to decide which id it answers to
/// (`ViewerOpening.sourceID(forCell:)`). The grid scrolls the shown cell into view as the
/// viewer pages, unanimated and behind an opaque cover, so the zoom back has somewhere to land.
struct ViewerCover: ViewModifier {
    /// The viewer's opening while it is up, or nil.
    @Binding var opening: ViewerOpening?
    /// The pictures the viewer pages through, given the one it opened on.
    let entries: (ViewerOpening) -> [CachedEntry]

    @Namespace private var zoom

    func body(content: Content) -> some View {
        content
            .environment(\.openLibraryItem) { opening = ViewerOpening(opened: $0) }
            .environment(\.viewerOpening, opening)
            .environment(\.viewerNamespace, zoom)
            .fullScreenCover(item: $opening) { open in
                LibraryViewer(entries: entries(open), opening: open.opened.fileName)
                    .environment(\.viewerPaged) { opening?.shown = $0 }
                    .navigationTransition(.zoom(sourceID: open.opened.fileName, in: zoom))
            }
    }
}

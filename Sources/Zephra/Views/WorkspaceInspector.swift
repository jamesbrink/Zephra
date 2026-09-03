import SwiftUI
import ZephraEngine

/// The column at the trailing edge of the window: what is known about the image being looked
/// at, whichever pane is showing.
///
/// The one place that turns a `WorkspacePane` into an inspector, the twin of `WorkspaceDetail`.
/// In the library it describes the grid's selection; on the canvas, the picture on it. It sits
/// under the toolbar rather than beside it, because a column that reached the title bar split
/// the toolbar at its edge and squeezed the sort and model menus into whatever width it had.
struct WorkspaceInspector: View {
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        switch workspace.pane {
        case .canvas:
            CanvasInspector()
        case .library:
            LibraryInspector()
        }
    }
}

#Preview("Canvas") {
    WorkspaceInspector()
        .frame(width: 320, height: 700)
        .environment(ImageCache())
        .environment(ThumbnailCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 8))
        .environment(GenerationStore.preview(state: .ready, image: PreviewImages.sample()))
}

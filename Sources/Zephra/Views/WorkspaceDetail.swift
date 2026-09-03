import SwiftUI
import ZephraEngine

/// The wide half of the window: whichever pane is showing.
///
/// The one place that turns a `WorkspacePane` into a view, so adding a pane is a case here and
/// a case in the picker, and nothing else in the app has to learn its name.
struct WorkspaceDetail: View {
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        switch workspace.pane {
        case .canvas:
            CanvasPane()
        case .library:
            LibraryDetail()
        }
    }
}

#Preview("Canvas") {
    WorkspaceDetail()
        .frame(width: 900, height: 700)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(LibraryIndex.preview(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready, image: PreviewImages.sample()))
}

#Preview("Library") {
    WorkspaceDetail()
        .frame(width: 900, height: 700)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .library))
        .environment(LibraryIndex.preview(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}

import SwiftUI
import ZephraEngine

/// The wide half of the window: whichever pane is showing, with the inspector beside it when
/// it is out.
///
/// The one place that turns a `WorkspacePane` into a view, so adding a pane is a case here and
/// a case in the picker, and nothing else in the app has to learn its name.
///
/// The inspector is a column beside the pane rather than SwiftUI's own `.inspector`, which is a
/// full-height one: it divided the toolbar at its edge and left the sort and model menus
/// cramped into its width, the sort menu collapsed to an icon. Under the toolbar the whole
/// title bar stays one strip. The column is a fixed width rather than a split: an `HSplitView`
/// handed it its maximum and laid the canvas out for a width it did not have.
struct WorkspaceDetail: View {
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        HStack(spacing: 0) {
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if workspace.inspectorVisible {
                Divider()
                WorkspaceInspector()
                    .frame(width: Self.inspectorWidth)
            }
        }
    }

    /// Wide enough for a 1024-wide picture's facts on one line each, and the same on both panes.
    private static let inspectorWidth: CGFloat = 320

    @ViewBuilder
    private var pane: some View {
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
        .frame(width: 1100, height: 700)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready, image: PreviewImages.sample()))
}

#Preview("Library") {
    WorkspaceDetail()
        .frame(width: 1100, height: 700)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .library))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}

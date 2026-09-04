import SwiftUI
import ZephraEngine

/// What is known about whatever the canvas is showing.
///
/// Three real branches, in the order the canvas itself decides them. While the canvas is
/// following the run it is the run: what was asked for, how far along it is, and the way out.
/// Once a picture is on the canvas and the folder scan has indexed the file it went to, it is
/// the library's own inspector, tags and albums included, so a picture reads the same way on
/// both panes. For the second or so before that scan catches up — and for a picture that was
/// never saved — it is the facts the session holds in memory, the same lines with nothing to
/// file under yet.
///
/// The last branch is a fallback rather than a state anyone sees: the canvas is empty and not
/// following a run only when `GenerationStore.hasPicture` is false, and `WorkspaceDetail` takes
/// the whole column away then.
struct CanvasInspector: View {
    @Environment(GenerationStore.self) private var store
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        Group {
            if store.isShowingRun {
                RunningRunInspector()
            } else if let item {
                SingleImageInspector(item: item)
            } else if let image = store.current {
                FreshImageInspector(image: image)
            } else {
                ContentUnavailableView("Nothing on the canvas", systemImage: "photo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The library's record of the picture on the canvas, by the file it was written to.
    private var item: LibraryItem? { index.canvasItem(for: store) }
}

#Preview("Nothing on the canvas") {
    CanvasInspector()
        .frame(width: 320, height: 620)
        .environment(ImageCache())
        .environment(PreviewImages.library(count: 8))
        .environment(GenerationStore.preview(state: .ready))
}

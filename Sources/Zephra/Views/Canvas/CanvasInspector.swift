import SwiftUI
import ZephraEngine

/// What is known about the picture on the canvas.
///
/// Once the file has been indexed it is the library's own inspector, tags and albums included,
/// so a picture reads the same way on both panes. For the second or so before the folder scan
/// catches up — and for a picture that was never saved — it is the facts the session holds in
/// memory, which are the same lines with nothing to file under yet.
///
/// The last branch is a fallback rather than a state anyone sees: `WorkspaceDetail` takes the
/// column away when the canvas is empty.
struct CanvasInspector: View {
    @Environment(GenerationStore.self) private var store
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        Group {
            if let item {
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
    private var item: LibraryItem? {
        guard let url = store.current?.fileURL else { return nil }
        return index.item(for: url.standardizedFileURL.path(percentEncoded: false))
    }
}

#Preview("Nothing on the canvas") {
    CanvasInspector()
        .frame(width: 320, height: 620)
        .environment(ImageCache())
        .environment(PreviewImages.library(count: 8))
        .environment(GenerationStore.preview(state: .ready))
}

import SwiftUI
import ZephraCore
import ZephraEngine

/// What can be done to a picture this session made that the library has not indexed yet.
///
/// `LibraryItemMenu` is the menu every indexed image wears; this is the handful of the same
/// actions that still make sense before there is a `LibraryItem` to hand it — favourite, export,
/// copy, reveal, use as reference, delete — worded and ordered to match. Once the folder scan
/// catches up, `CanvasInspector`'s lookup finds the file and the picture's menu becomes
/// `LibraryItemMenu` instead; this one is only ever shown in the moment before that.
struct FreshImageMenu: View {
    /// The image the menu acts on.
    let image: GeneratedImage

    @Environment(GenerationStore.self) private var store

    var body: some View {
        CanvasFavouriteButton(image: image)
        Divider()
        Button("Export…") { ImageExport.saveAs(image) }
        Button("Copy") { ImageExport.copyToPasteboard(image) }
        Button("Reveal in Finder") { ImageExport.revealInFinder(image) }
        if store.descriptor.capabilities.supportsReferenceImage {
            Button("Use as Reference") { ReferenceAdoption.adopt(image, into: store) }
        }
        Divider()
        // Nothing is asked first: the file goes to Recently Deleted, where Put Back has thirty
        // days, and a dialog on every discarded image would be in the way.
        Button("Delete", role: .destructive) { store.delete(image.id) }
    }
}

#Preview("Menu") {
    Text("Right-click")
        .padding(40)
        .contextMenu { FreshImageMenu(image: PreviewImages.sample()) }
        .environment(ImageCache())
        .environment(PreviewImages.library(count: 4))
        .environment(GenerationStore.preview(state: .ready))
}

import SwiftUI
import ZephraCore
import ZephraEngine

/// Which menu the picture on the canvas wears: the library's own once the folder scan has
/// indexed the file it was written to, or `FreshImageMenu` for the moment before that.
///
/// A view of its own rather than the choice inline in `CanvasView`, which already holds its
/// three stored properties and would need both the index and the store as more.
struct CanvasImageMenu: View {
    /// The picture on the canvas.
    let image: GeneratedImage

    @Environment(GenerationStore.self) private var store
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        if let item = index.canvasItem(for: store) {
            LibraryItemMenu(items: [item], offersOpen: false)
        } else {
            FreshImageMenu(image: image)
        }
    }
}

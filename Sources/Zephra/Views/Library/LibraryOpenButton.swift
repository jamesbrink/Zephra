import SwiftUI
import ZephraEngine

/// "Open in canvas", wherever it is offered: the cell's menu, the inspector, the menu bar.
///
/// A view of its own rather than a repeated `Button`, because opening is the same act in all
/// three places and only the styling differs — which is inherited, so each caller says how it
/// should look and none of them says again what it does. The label fills whatever width it is
/// given, which is what makes the inspector's buttons line up; a menu builds its item from the
/// text and ignores the frame.
struct LibraryOpenButton: View {
    /// The image to put on the canvas.
    let item: LibraryItem

    @Environment(\.openLibraryItem) private var openLibraryItem
    @Environment(GenerationStore.self) private var store

    var body: some View {
        // Absent when the picture is on the canvas already: the offer means nothing there,
        // and the canvas's own menu is one of the places this button is drawn.
        if store.current?.fileURL?.standardizedFileURL != item.url.standardizedFileURL {
            Button { openLibraryItem(item) } label: {
                Text("Open in canvas").frame(maxWidth: .infinity)
            }
        }
    }
}

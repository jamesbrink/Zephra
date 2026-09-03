import SwiftUI

/// "Open in canvas", wherever it is offered: the cell's menu, the inspector, the menu bar.
///
/// A view of its own rather than a repeated `Button`, because opening is the same act in all
/// three places and only the styling differs — which is inherited, so each caller says how it
/// should look and none of them says again what it does.
struct LibraryOpenButton: View {
    /// The image to put on the canvas.
    let item: LibraryItem

    @Environment(\.openLibraryItem) private var openLibraryItem

    var body: some View {
        Button("Open in canvas") { openLibraryItem(item) }
    }
}

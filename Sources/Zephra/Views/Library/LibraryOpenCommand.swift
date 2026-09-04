import SwiftUI
import ZephraEngine

/// Return shows the one selected image full size, the same thing a double-click does.
///
/// A modifier rather than more lines in `LibraryGrid`, because it is a whole small behaviour —
/// a key, a condition, an action — and because the grid has as many of these attached to it as
/// it can hold without becoming the thing that knows everything.
struct LibraryOpenCommand: ViewModifier {
    /// What is selected in the grid.
    let selection: LibrarySelection

    @Environment(LibraryIndex.self) private var index
    @Environment(\.viewLibraryItem) private var viewLibraryItem

    func body(content: Content) -> some View {
        content.onKeyPress(.return) {
            guard let id = selection.single, let item = index.item(for: id) else { return .ignored }
            viewLibraryItem(item)
            return .handled
        }
    }
}

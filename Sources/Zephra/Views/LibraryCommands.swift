import SwiftUI
import ZephraEngine

/// The menu bar's half of the library: choosing everything, and marking favourites.
///
/// Select All is bound to the grid's own focus rather than to the pane, so ⌘A in the sidebar's
/// search field still means the text. The favourite reads the pane instead, because it does not
/// collide with anything and should keep working while the inspector has the keyboard.
struct LibraryCommands: Commands {
    @FocusedValue(\.focusedLibraryGrid) private var grid
    @FocusedValue(\.librarySelection) private var selection
    @FocusedValue(\.libraryIndex) private var index

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Select All Images") { selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(grid == nil || index == nil)
            Button(favouriteTitle) { index?.toggleFavourite(chosen) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(chosen.isEmpty)
        }
    }

    private func selectAll() {
        guard let grid, let index else { return }
        grid.apply(LibraryCursor.selectAll(in: index.sections))
    }

    private var chosen: Set<LibraryItem.ID> { selection?.ids ?? [] }

    /// The word is what the images are about to become, which for a mixed selection is
    /// "favourite" — one press should make them agree rather than invert each of them.
    private var favouriteTitle: String {
        guard let index, !chosen.isEmpty,
              chosen.allSatisfy({ index.item(for: $0)?.isFavourite == true })
        else { return "Add to Favourites" }
        return "Remove from Favourites"
    }
}

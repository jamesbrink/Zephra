import SwiftUI
import ZephraEngine

/// The menu bar's half of the library: choosing everything, marking favourites, and stepping
/// back out of the viewer.
///
/// Select All is bound to the grid's own focus rather than to the pane, so ⌘A in the sidebar's
/// search field still means the text. The favourite reads the pane instead, because it does not
/// collide with anything and should keep working while the inspector has the keyboard. Back to
/// Grid reads `workspace` directly, handed over by the composition root the way
/// `WorkspaceCommands` already takes it, rather than through a focused value: it needs to work
/// the moment the viewer is up, before anything inside it has taken the keyboard.
struct LibraryCommands: Commands {
    /// The window's selection, handed over by the composition root.
    let workspace: WorkspaceSelection

    @FocusedValue(\.focusedLibraryGrid) private var grid
    @FocusedValue(\.librarySelection) private var selection
    @FocusedValue(\.libraryIndex) private var index

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Select All Images") { selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                // The viewer publishes the grid's key so Save, Copy and Delete act on the
                // picture it shows, but there is no grid to choose everything in: ⌘A there
                // would select every image under a view of one, and the next ⌘⌫ take them all.
                .disabled(grid == nil || index == nil || workspace.viewing != nil)
            Button(favouriteTitle) { index?.toggleFavourite(chosen) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(chosen.isEmpty)
            Button("Back to Grid") { workspace.viewing = nil }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(workspace.viewing == nil)
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
        else { return "Add to Favorites" }
        return "Remove from Favorites"
    }
}

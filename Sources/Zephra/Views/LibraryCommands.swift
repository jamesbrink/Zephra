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
            // Two items in this menu carry ⌘A: the one below, and the Select All SwiftUI
            // synthesizes into the `.pasteboard` group just above it. At most one is ever
            // enabled — the synthesized one is nil-targeted at `selectAll:` and disables itself
            // when nothing in the responder chain implements that selector, which over the grid
            // nothing does — so the keystroke reaches this item. That works, and it rests on
            // that: a SwiftUI release that implemented `selectAll:` on its own focusable view
            // would shadow this item, and the symptom would be ⌘A quietly no longer selecting
            // anything here.
            //
            // Nothing better is available, and each alternative costs more than the duplicate.
            // Putting `selectAll:` in the responder chain ourselves is the fix that would let
            // the synthesized item simply work, but nil-targeted dispatch walks the first
            // responder and its superviews and never a sibling, so it needs the grid re-hosted
            // inside an `NSView` of our own. Catching ⌘A with `onKeyPress` instead leaves every
            // Select All in the menu greyed while the chord works, which is the one thing the
            // menu bar here exists not to do. And replacing the whole `.pasteboard` group to
            // own the single item takes Cut, Copy, Paste and Delete with it, away from AppKit's
            // validation and into being permanently enabled and silently inert in every text
            // field in the app.
            //
            // `ZephraCommands` does dodge a synthesized chord where it can — Copy Image is
            // ⇧⌘C, leaving plain ⌘C to the responder chain — but there is no second chord for
            // Select All that anyone would go looking for.
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

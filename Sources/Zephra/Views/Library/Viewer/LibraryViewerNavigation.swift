import SwiftUI
import ZephraEngine

/// The viewer's keyboard, and the double-click that undoes a double-click: Escape and a second
/// click return to the grid, and the arrow keys — left/right and up/down alike, since either
/// pair reads naturally as "the other one" — step to the next or previous image in the grid's
/// own order.
///
/// A modifier of its own, the same shape as `LibraryOpenCommand` and `LibraryQuickLook`, rather
/// than more stored properties on `LibraryViewer`, which already holds its three. It changes
/// only `workspace.viewing`; keeping the grid's selection in step with wherever that lands is
/// `LibraryPane`'s job; see its own doc comment.
struct LibraryViewerNavigation: ViewModifier {
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(LibraryIndex.self) private var index
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            // `focusable()` only makes the viewer eligible; the keyboard stays wherever it
            // was — the search field, the grid that has just gone — unless it is asked for.
            // Without it Escape and the arrows do nothing and the file commands fall back to
            // the canvas. After one yield, as `AlbumNameField` does: focus set on the first
            // pass, before the view is in a window, is dropped.
            .task {
                await Task.yield()
                isFocused = true
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { close() }
            .onKeyPress(.escape) { close(); return .handled }
            .onKeyPress(.leftArrow) { step(.previous) }
            .onKeyPress(.upArrow) { step(.previous) }
            .onKeyPress(.rightArrow) { step(.next) }
            .onKeyPress(.downArrow) { step(.next) }
    }

    private func close() { workspace.viewing = nil }

    private func step(_ direction: LibraryViewerStep.Direction) -> KeyPress.Result {
        guard let id = workspace.viewing,
              let neighbour = LibraryViewerStep.neighbour(of: id, direction: direction, in: index.sections)
        else { return .ignored }
        workspace.viewing = neighbour
        return .handled
    }
}

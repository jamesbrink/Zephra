import SwiftUI
import ZephraEngine

/// What the library publishes to the menu bar, and how much of the window each thing means.
///
/// Two selections rather than one, because "the library is showing" and "the grid has the
/// keyboard" are different questions and the menu bar needs both. A command that acts on files
/// — Save as, Copy, Reveal, Delete, Select All — must mean the library only while the grid is
/// where the typing would go. ⌘A while the cursor is in the sidebar's search field means the
/// text, and ⌘⌫ there means the line; a scene-wide binding would take both away.
///
/// The two that are about the pane rather than about the keyboard — the size shortcuts, the
/// favourite — read the scene value, so they keep working while the inspector has the focus.
extension FocusedValues {
    /// The library pane's selection, published for as long as that pane is on screen.
    @Entry var librarySelection: LibrarySelection?
    /// The same selection, published only while the grid itself has the keyboard.
    @Entry var focusedLibraryGrid: LibrarySelection?
    /// The library those images came from, so a command can act on the files behind them.
    @Entry var libraryIndex: LibraryIndex?
    /// Makes an album and starts naming it in the sidebar, or nil when there is no sidebar
    /// listening — which is every moment the library pane is not up.
    ///
    /// An action rather than a piece of state, because the naming happens in `SidebarView`'s own
    /// `@State` and the menu bar has no way into it. Publishing the action instead means ⌘N and
    /// the New Album bar are the same line of code, and "is there anything to do" is answered by
    /// whether anyone published it rather than by the menu re-deriving which pane is showing.
    /// Spelled `@MainActor` because that is what it is: a method on a view, published by one
    /// view and called from the menu bar, both of them on the main actor.
    @Entry var newAlbum: (@MainActor () -> Void)?
}

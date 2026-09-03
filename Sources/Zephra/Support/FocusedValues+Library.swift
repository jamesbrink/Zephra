import SwiftUI
import ZephraEngine

/// What the library pane publishes to the menu bar while it has the focus.
///
/// Save as, Copy, Reveal and Delete mean one thing on the canvas and another in the library,
/// and the menu bar is built once for the whole scene. A focused value is how the two panes
/// take turns: whichever is on screen publishes its selection, and the commands read whatever
/// is published — nil meaning the canvas, which is the state the app starts in.
extension FocusedValues {
    /// The images selected in the library grid, or nil when the library is not showing.
    @Entry var librarySelection: LibrarySelection?
    /// The library those images came from, so a command can act on the files behind them.
    @Entry var libraryIndex: LibraryIndex?
}

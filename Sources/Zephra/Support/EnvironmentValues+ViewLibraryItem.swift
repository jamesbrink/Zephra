import SwiftUI
import ZephraEngine

/// How the grid's double-click and Return ask for the full-size viewer, the twin of
/// `openLibraryItem`.
///
/// `RootView` provides it beside `openLibraryItem`, above both the pane and the inspector, for
/// the same reason: a cell that wants it should not have to reach into the window's own
/// selection to say so.
extension EnvironmentValues {
    /// Shows one library image full size, in the library pane itself, rather than putting it on
    /// the canvas. Does nothing outside the window's view tree.
    @Entry var viewLibraryItem: (LibraryItem) -> Void = { _ in }
}

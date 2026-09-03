import SwiftUI

/// How anything inside the library pane asks for an image to be put on the canvas.
///
/// Opening is two things at once — the store reads the file, and the window changes pane — and
/// four places ask for it: a double-click, Return, the cell's menu, and the inspector's button.
/// Handing it down as one closure means a cell that wants it does not have to hold the store
/// and the window's selection to say so.
///
/// `RootView` provides it, above both the pane and the inspector. The inspector is attached to
/// the split view, so anything provided inside the pane would not reach it.
extension EnvironmentValues {
    /// Puts one library image on the canvas. Does nothing outside the window's view tree.
    @Entry var openLibraryItem: (LibraryItem) -> Void = { _ in }
}

import SwiftUI

/// How anything inside the library pane asks for an image to be put on the canvas.
///
/// Opening is two things at once — the store reads the file, and the window changes pane — and
/// three places ask for it: a double-click, the cell's menu, and the inspector's button. Handing
/// it down as one closure means the pane decides what opening means, and a cell that wants it
/// does not have to hold the store and the window's selection to say so.
extension EnvironmentValues {
    /// Puts one library image on the canvas. Does nothing outside the library pane.
    @Entry var openLibraryItem: (LibraryItem) -> Void = { _ in }
}

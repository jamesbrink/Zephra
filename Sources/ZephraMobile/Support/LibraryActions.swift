import SwiftUI

/// The four things a picture's menu asks for that it cannot do itself.
///
/// A menu is content, not a presentation context: a `contextMenu` cannot raise a sheet, and a
/// button buried three views deep should not be the thing that owns one. So each of these is a
/// closure in the environment, handled once by whichever surface is presenting — which is the
/// Mac's `\.viewLibraryItem` and `\.openLibraryItem` pattern, for the Mac's reason.
///
/// `LibraryRequests` is what fills them in. A surface that does not apply it gets the defaults,
/// which do nothing, so a preview of a cell on its own still draws its menu.
extension EnvironmentValues {
    /// Opens one picture full size.
    @Entry var openLibraryItem: (CachedEntry) -> Void = { _ in }
    /// Raises the tag sheet over one picture.
    @Entry var tagLibraryItem: (CachedEntry) -> Void = { _ in }
    /// Asks whether to delete one picture, and deletes it if the answer is yes.
    @Entry var confirmDeleteLibraryItem: (CachedEntry) -> Void = { _ in }
    /// Fetches one picture's file and offers it to the rest of the phone.
    @Entry var shareLibraryItem: (CachedEntry) -> Void = { _ in }
}

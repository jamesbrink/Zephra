import Observation
import ZephraEngine

/// What the reference picker sheet is showing and has chosen: the search text and the one
/// image picked, if any.
///
/// One `@Observable` object rather than two `@State` properties threaded down as bindings, so
/// the sheet, its search field, and its grid can each share the one thing that changes while
/// staying inside the three-stored-property rule — the way `LibrarySelection` already does for
/// the main grid.
@Observable
final class ReferencePickerSelection {
    /// What the search field has typed, matched the way the library grid matches free text.
    var text: String = ""
    /// The image a click or an arrow key has landed on, or nil before one has.
    var item: LibraryItem?
    /// How many cells the grid is laying out per row, which is what up and down move by. The
    /// grid measures itself and writes it here, the way `LibrarySelection.columns` is kept.
    var columns: Int = 1
    /// Bumped by the search field when a down arrow should hand the keyboard to the grid;
    /// `ReferencePickerKeyboard` takes focus on every change.
    var gridFocusRequests = 0
}

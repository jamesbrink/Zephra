import SwiftUI
import ZephraEngine

/// The picker grid's keyboard: the arrow keys move the pick through the matches the way they
/// move the library grid's selection, and a request from the search field brings the
/// keyboard here.
///
/// The same `LibraryCursor` arithmetic as the library grid, over one section holding every
/// match, so a row is the number of columns the grid measured and down from the last row
/// goes nowhere. Return is not handled here: it is the sheet's own default action, Use.
struct ReferencePickerKeyboard: ViewModifier {
    /// What is picked, and how many cells a row holds.
    let selection: ReferencePickerSelection
    /// The pictures the grid is showing, in its order.
    let matches: [LibraryItem]

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            // The ring the system would draw round the whole scroll view says nothing; the
            // ring round the picked cell is what shows where the keyboard is.
            .focusEffectDisabled()
            .focused($isFocused)
            .onMoveCommand { move($0) }
            // A down arrow in the search field lands here, on the first picture when nothing
            // is picked yet, so the field and the grid read as one list to walk down.
            .onChange(of: selection.gridFocusRequests) {
                isFocused = true
                if selection.item == nil { selection.item = matches.first }
            }
    }

    private func move(_ command: MoveCommandDirection) {
        guard let heading = LibraryCursor.Direction(command) else { return }
        let picked = selection.item?.id
        let outcome = LibraryCursor.move(
            heading,
            in: [LibrarySection(day: .distantPast, items: matches)],
            columns: selection.columns,
            selection: picked.map { [$0] } ?? [],
            anchor: picked
        )
        guard let outcome else { return }
        selection.item = matches.first { outcome.ids.contains($0.id) }
    }
}

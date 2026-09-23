import SwiftUI
import ZephraEngine

/// The picker grid's keyboard: the arrow keys move the pick through the matches the way they
/// move the library grid's selection, shift-arrow grows the run on a model that reads several,
/// and a request from the search field brings the keyboard here.
///
/// The same `LibraryCursor` arithmetic as the library grid, over one section holding every
/// match, so a row is the number of columns the grid measured and down from the last row
/// goes nowhere. Return is not handled here: it is the sheet's own default action, Use.
///
/// Shift-arrow needs `onKeyPress`, since `onMoveCommand` reports no modifiers; a press without
/// shift is answered `.ignored` and falls through to `onMoveCommand`, which is what the plain
/// arrows have always walked by.
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
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                guard press.modifiers.contains(.shift), let heading = direction(press.key) else {
                    return .ignored
                }
                selection.move(heading, in: matches, extending: true)
                return .handled
            }
            .onMoveCommand { command in
                guard let heading = LibraryCursor.Direction(command) else { return }
                selection.move(heading, in: matches)
            }
            // A down arrow in the search field lands here, on the first picture when nothing
            // is picked yet, so the field and the grid read as one list to walk down.
            .onChange(of: selection.gridFocusRequests) {
                isFocused = true
                if selection.ids.isEmpty, let first = matches.first {
                    selection.click(first.id, in: matches, modifiers: [])
                }
            }
    }

    private func direction(_ key: KeyEquivalent) -> LibraryCursor.Direction? {
        if key == .upArrow { return .up }
        if key == .downArrow { return .down }
        if key == .leftArrow { return .left }
        if key == .rightArrow { return .right }
        return nil
    }
}

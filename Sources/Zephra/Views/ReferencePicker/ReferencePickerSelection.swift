import Foundation
import Observation
import ZephraEngine

/// What the reference picker sheet is showing and has chosen: the search text, and the pictures
/// picked so far in the order the grid lists them.
///
/// One `@Observable` object rather than several `@State` properties threaded down as bindings, so
/// the sheet, its search field, and its grid can each share the one thing that changes while
/// staying inside the three-stored-property rule — the way `LibrarySelection` already does for
/// the main grid.
///
/// The selection rules are `LibraryCursor`'s, the same ones the library grid walks by: a plain
/// click picks one, a command-click toggles one, a shift-click takes the run between the anchor
/// and what was clicked, and a shift-arrow grows or shrinks that run. What is added here is the
/// cap: a model reads a stated number of pictures, and a selection that grew past it would offer
/// a Use button promising something the well would then trim.
@Observable
final class ReferencePickerSelection {
    /// What the search field has typed, matched the way the library grid matches free text.
    var text: String = ""
    /// The pictures picked so far, by id, which is what a cell asks to draw its ring.
    var ids: Set<LibraryItem.ID> = []
    /// The same pictures in the grid's own order, which is the order the model reads them in.
    /// Kept beside the set rather than derived at the footer, because the footer has no index
    /// to derive it from and a set of ids has no order to derive it with.
    var picked: [LibraryItem] = []
    /// The fixed end a shift-selection extends from.
    var anchor: LibraryItem.ID?
    /// How many cells the grid is laying out per row, which is what up and down move by. The
    /// grid measures itself and writes it here, the way `LibrarySelection.columns` is kept.
    var columns: Int = 1
    /// Bumped by the search field when a down arrow should hand the keyboard to the grid;
    /// `ReferencePickerKeyboard` takes focus on every change.
    var gridFocusRequests = 0
    /// How many pictures may be picked at once: the model's own count, so a one-picture model's
    /// sheet behaves exactly as it always has.
    let limit: Int

    /// Creates a selection for a model that reads `limit` pictures.
    init(limit: Int = 1) {
        self.limit = max(1, limit)
    }

    /// Whether more than one picture may be picked at all.
    var allowsSeveral: Bool { limit > 1 }

    /// How many are picked.
    var count: Int { ids.count }

    /// What the sheet's confirming button says, which has to name the number when there is
    /// one: a Use that quietly took four pictures would be a Use nobody could count.
    var useTitle: String {
        count > 1 ? "Use \(count) as References" : "Use"
    }

    /// What a click on `id` does, given what was held down.
    func click(
        _ id: LibraryItem.ID, in matches: [LibraryItem], modifiers: LibraryCursor.ClickModifiers
    ) {
        let modifiers = allowsSeveral ? modifiers : []
        take(
            LibraryCursor.click(
                id, in: sections(matches), modifiers: modifiers, selection: ids, anchor: anchor),
            in: matches)
    }

    /// What an arrow key does, extending the run while shift is held.
    func move(
        _ direction: LibraryCursor.Direction, in matches: [LibraryItem], extending: Bool = false
    ) {
        let outcome = LibraryCursor.move(
            direction, in: sections(matches), columns: columns, selection: ids, anchor: anchor,
            extending: extending && allowsSeveral)
        guard let outcome else { return }
        take(outcome, in: matches)
    }

    /// Drops whatever is no longer on screen — hidden by the search, or gone from the folder
    /// while the sheet was up — since Use would otherwise adopt a picture that is not there.
    func prune(to matches: [LibraryItem]) {
        let shown = Set(matches.map(\.id))
        guard !ids.isSubset(of: shown) else {
            picked = matches.filter { ids.contains($0.id) }
            return
        }
        ids.formIntersection(shown)
        picked = matches.filter { ids.contains($0.id) }
        if let anchor, !shown.contains(anchor) { self.anchor = ids.first }
    }

    /// Applies one cursor outcome, trimmed to the cap: the pictures nearest the anchor survive,
    /// because that is the end the person is working from.
    private func take(_ outcome: LibraryCursor.Outcome, in matches: [LibraryItem]) {
        anchor = outcome.anchor
        guard outcome.ids.count > limit else {
            ids = outcome.ids
            picked = matches.filter { ids.contains($0.id) }
            return
        }
        let order = matches.map(\.id).filter(outcome.ids.contains)
        let pivot = outcome.anchor.flatMap(order.firstIndex(of:)) ?? 0
        let kept = order.enumerated()
            .sorted { abs($0.offset - pivot) < abs($1.offset - pivot) }
            .prefix(limit)
            .map(\.element)
        ids = Set(kept)
        picked = matches.filter { ids.contains($0.id) }
    }

    private func sections(_ matches: [LibraryItem]) -> [LibrarySection] {
        [LibrarySection(day: .distantPast, items: matches)]
    }
}

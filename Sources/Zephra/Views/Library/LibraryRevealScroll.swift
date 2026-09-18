import SwiftUI
import ZephraEngine

/// Brings the picture something outside the window asked for into view.
///
/// The grid already scrolls to a lone selection when it appears, which covers the ordinary
/// case: a click on a notification while the canvas is up builds this grid fresh. What it does
/// not cover is the grid that is already on screen, where nothing appears and nothing scrolls,
/// and a picture three screens down reads as a click that did nothing.
///
/// A modifier rather than more lines in `LibraryGrid`, which is at its three stored properties
/// already; `LibraryGridKeyboard` beside it is the same split for the same reason.
/// It answers a reveal through one callback that selects and scrolls together.
/// A separate observer in the enclosing pane would run
/// after this modifier consumed the token and miss the selection.
///
/// Whether there is an ask to answer, and whether this is the moment to answer it, is
/// `WorkspaceSelection.answerReveal`'s judgement and not this view's: the selection is what
/// consumes, so the rule is one, it is testable without a scroll view, and every mount of the
/// grid answers a given ask at most once. Watching `index.sections` beside the token is what
/// makes the rule reachable: a reveal widens the query so the picture is listable again, and the
/// index catches up a beat later, so the sections arriving is the first moment there is anywhere
/// for `scrollTo` to anchor on.
struct LibraryRevealScroll: ViewModifier {
    /// Selects and scrolls together, so consumption cannot overtake another observer.
    let show: (LibraryItem.ID) -> Void

    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(LibraryIndex.self) private var index

    func body(content: Content) -> some View {
        content
            // `initial`, because a grid built in answer to the ask has already missed the change.
            .onChange(of: workspace.revealToken, initial: true) { _, _ in revealIfListed() }
            // The second waking, for the grid already on screen: the widened query reaches
            // the index some time after the ask, and its sections arriving is the first
            // moment there is anywhere to scroll to.
            .onChange(of: index.sections) { _, _ in revealIfListed() }
    }

    /// Asks the selection what to bring into view and scrolls to it, or does neither.
    ///
    /// A picture nothing lists — deleted, or gone from the library with the folder it came from —
    /// leaves the ask standing: `revealing` stays readable by design, and no scroll an id can
    /// never match is worth making.
    private func revealIfListed() {
        let sections = index.sections
        guard let id = workspace.answerReveal(listed: { id in
            sections.contains(where: { $0.items.contains { $0.id == id } })
        }) else { return }
        show(id)
    }
}

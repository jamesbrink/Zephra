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
/// already; `LibraryGridKeyboard` beside it is the same split for the same reason. It reads
/// `WorkspaceSelection.unansweredReveal` rather than the selection, so it does not depend on
/// whether the pane above has applied the selection yet — and an ask already answered reads as
/// nothing, so a grid mounted later does not scroll back to a picture nobody asked for again.
///
/// It scrolls only once the list on screen actually holds the asked-for picture, and it is
/// what consumes the ask. A reveal can widen the query — `WorkspaceSelection.reveal` does, so
/// the picture is listable again — and the index catches up a beat later: `RootView` copies
/// `workspace.query` into `index.query` from an observer of its own, which can land after the
/// pass this token change fires in. Scrolling then would run against the stale sections, where
/// `scrollTo` finds nothing to anchor on, and an ask consumed regardless would stay stranded
/// off screen with nothing left to retry it. Watching `index.sections` as well is the retry,
/// and consuming on the scroll is what keeps every earlier mount answering an ask once.
struct LibraryRevealScroll: ViewModifier {
    /// The grid's scroll view, for revealing whatever was asked for.
    let proxy: ScrollViewProxy

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

    /// Scrolls to the asked-for picture and answers the ask — but only once the sections on
    /// screen list it, since `scrollTo` anchors on what the grid can actually lay out. A
    /// picture that nothing lists — deleted, or gone from the library with the folder it came
    /// from — leaves the ask standing: `revealing` stays readable by design, and no scroll
    /// the id can never match is worth making.
    private func revealIfListed() {
        guard let id = workspace.unansweredReveal else { return }
        guard index.sections.contains(where: { $0.items.contains { $0.id == id } }) else { return }
        proxy.scrollTo(id, anchor: .center)
        workspace.markRevealConsumed(workspace.revealToken)
    }
}

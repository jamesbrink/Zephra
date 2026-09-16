import SwiftUI
import ZephraEngine

/// Brings the picture something outside the window asked for into view.
///
/// The grid already scrolls to a lone selection when it appears, which covers the ordinary
/// case: a click on a notification while the canvas is up builds this grid fresh. What it does
/// not cover is the grid that is already on screen, where nothing appears and nothing scrolls,
/// and a picture selected three screens down reads as a click that did nothing.
///
/// A modifier rather than more lines in `LibraryGrid`, which is at its three stored properties
/// already; `LibraryGridKeyboard` beside it is the same split for the same reason. It reads
/// `WorkspaceSelection.revealing` rather than the selection, so it does not depend on whether
/// the pane above has applied the selection yet.
struct LibraryRevealScroll: ViewModifier {
    /// The grid's scroll view, for revealing whatever was asked for.
    let proxy: ScrollViewProxy

    @Environment(WorkspaceSelection.self) private var workspace

    func body(content: Content) -> some View {
        // `initial`, because a grid built in answer to the ask has already missed the change.
        content.onChange(of: workspace.revealToken, initial: true) { _, _ in
            guard let id = workspace.revealing else { return }
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

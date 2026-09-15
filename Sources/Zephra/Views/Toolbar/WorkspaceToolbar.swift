import SwiftUI

/// The title bar: which pane at the leading edge, and at the trailing edge everything about
/// what is being looked at — the zoom slider and sort order in the library, the model on the
/// canvas — then the inspector and settings on both.
///
/// The pane picker is the only thing at the leading edge, beside the sidebar's own toggle: it
/// is where the system's own apps put a switcher, and it is the one item that means the same
/// thing on both panes, which is what keeps the two toolbars symmetric — a library window and a
/// canvas window differ only in the middle of the trailing group, not in how much of the bar
/// they use.
///
/// It stores nothing and decides nothing. Each item is a small view that reads the one piece
/// of state it acts on, which is what lets a toolbar item hide itself on the wrong pane
/// without the toolbar having to know why.
struct WorkspaceToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) { WorkspacePicker() }
        ToolbarItemGroup(placement: .primaryAction) {
            LibraryZoomSlider()
            LibrarySortMenu()
            ModelMenu()
            ModelLoadButton()
            InspectorToggle()
            SettingsButton()
        }
    }
}

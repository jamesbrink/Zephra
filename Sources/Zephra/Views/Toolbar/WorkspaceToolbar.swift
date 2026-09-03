import SwiftUI

/// The title bar: which pane at the leading edge, and at the trailing edge how the library is
/// ordered, which model, the inspector, and settings.
///
/// The pane picker sits at the leading edge, beside the sidebar's own toggle, rather than with
/// the other four: it is where the system's own apps put a switcher, and the four at the
/// trailing edge are all about what is being looked at rather than which pane is up.
///
/// It stores nothing and decides nothing. Each item is a small view that reads the one piece
/// of state it acts on, which is what lets a toolbar item hide itself on the wrong pane
/// without the toolbar having to know why.
struct WorkspaceToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) { WorkspacePicker() }
        ToolbarItemGroup(placement: .primaryAction) {
            LibrarySortMenu()
            ModelMenu()
            InspectorToggle()
            SettingsButton()
        }
    }
}

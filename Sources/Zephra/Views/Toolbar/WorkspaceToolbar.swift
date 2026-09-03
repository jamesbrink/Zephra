import SwiftUI

/// The title bar: which pane at the leading edge, and at the trailing edge how the library is
/// ordered, which model, the inspector, and settings.
///
/// The pane picker sits at the leading edge, beside the sidebar's own toggle, rather than with
/// the other four. A unified toolbar is split by the inspector's divider, and items are laid
/// out right to left from the window's edge, so a fifth trailing item spills across that
/// divider and lands on the content side — one group visibly torn in half, and it moves as the
/// inspector is resized. Putting the switcher at the leading edge is both stable and where the
/// system's own apps put one.
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

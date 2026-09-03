import SwiftUI

/// The right-hand end of the title bar: which pane, how the library is ordered, which model,
/// the inspector, and settings.
///
/// It stores nothing and decides nothing. Each item is a small view that reads the one piece
/// of state it acts on, which is what lets a toolbar item hide itself on the wrong pane
/// without the toolbar having to know why.
struct WorkspaceToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            WorkspacePicker()
            LibrarySortMenu()
            ModelMenu()
            InspectorToggle()
            SettingsButton()
        }
    }
}

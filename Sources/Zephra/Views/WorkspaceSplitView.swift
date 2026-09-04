import SwiftUI

/// The split itself: the sidebar column and whichever pane is up beside it.
///
/// Held apart from `RootView` for one piece of state, which column is showing. It is never
/// persisted: the sidebar should be out whenever the app opens, so a returning user sees it
/// exists, but the system's own toggle (⌃⌘S) is free to hide it for the rest of the run
/// without that choice following the user to the next launch.
struct WorkspaceSplitView: View {
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            WorkspaceDetail()
        }
    }
}

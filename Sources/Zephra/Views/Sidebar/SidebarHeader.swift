import SwiftUI

/// The top of the sidebar: the one search field, and the chips that narrow what it searches.
struct SidebarHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarSearch()
            ScopeChips()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

#Preview("Header") {
    SidebarHeader()
        .frame(width: 280)
        .environment(WorkspaceSelection(pane: .canvas))
}

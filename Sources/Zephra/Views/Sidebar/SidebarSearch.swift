import SwiftUI
import ZephraEngine

/// The one search field, at the top of the sidebar so it serves both panes.
///
/// A plain `TextField` rather than `.searchable`, which would attach itself to whichever pane
/// is showing and so become two fields that forget each other. Typing here while the canvas is
/// showing switches to the Library; clearing it comes back. `WorkspaceSelection` decides that,
/// which is why every keystroke goes through `setSearchText` rather than straight at the query.
struct SidebarSearch: View {
    @Environment(WorkspaceSelection.self) private var workspace
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("Search prompts and seeds", text: text)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isFocused)
            if !isFocused, workspace.query.text.isEmpty {
                Text(verbatim: "⌘F")
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.quaternary)
            }
        }
        .searchFieldChrome()
        .onChange(of: workspace.searchFocusToken) { isFocused = true }
        .accessibilityLabel("Search prompts and seeds")
    }

    private var text: Binding<String> {
        Binding(
            get: { workspace.query.text },
            set: { workspace.setSearchText($0) }
        )
    }
}

#Preview("Empty") {
    SidebarSearch()
        .padding()
        .frame(width: 280)
        .environment(WorkspaceSelection(pane: .canvas))
}

#Preview("Searching") {
    SidebarSearch()
        .padding()
        .frame(width: 280)
        .environment(WorkspaceSelection(
            pane: .library,
            query: LibraryQuery(text: "limestone")
        ))
}

import SwiftUI
import ZephraEngine

/// What is narrowing the grid, as chips that can be taken off.
///
/// The tokens are a view of the query rather than state beside it: the query says what its
/// tokens are, and removing one hands back the query without that part. That is why a chip
/// pressed in the sidebar and a chip taken off here cannot disagree — there is only one of
/// them, drawn twice.
struct LibraryFilterTokens: View {
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        HStack(spacing: 6) {
            ForEach(workspace.query.tokens, id: \.self) { token in
                Chip(token.title(albumName: index.name(of:)), isSelected: true) {
                    workspace.query = workspace.query.removing(token)
                }
            }
        }
    }
}

#Preview("Tokens") {
    LibraryFilterTokens()
        .padding(20)
        .environment(WorkspaceSelection(
            pane: .library,
            query: LibraryQuery(scope: .favourites, text: "limestone", tag: "night")
        ))
        .environment(LibraryIndex.preview(count: 38))
}

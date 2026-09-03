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
        // Nothing at all rather than an empty stack: the bar spaces its children, and an empty
        // stack still counts as one, which pushed the count off the grid's left edge.
        if !workspace.query.tokens.isEmpty {
            HStack(spacing: 6) {
                ForEach(workspace.query.tokens, id: \.self) { token in
                    Chip(token.title(albumName: index.name(of:)), isSelected: true) {
                        workspace.query = workspace.query.removing(token)
                    }
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
        .environment(PreviewImages.library(count: 38))
}

import SwiftUI
import ZephraCore
import ZephraEngine

/// Where to look, on the library pane: the standing collections, one row per model, the tags in
/// use, and the albums.
///
/// The library pane only. The canvas sidebar is the session timeline, which answers a different
/// question — what have I just made, and what is still coming — and a filing cabinet beside a
/// picture being worked on is a filing cabinet nobody opens.
struct SidebarSources: View {
    /// The album edit under way, owned by `SidebarView` so the rows here and the New Album bar
    /// below the list are looking at one value.
    @Binding var albumEdit: AlbumEdit?

    @Environment(WorkspaceSelection.self) private var workspace

    /// The collections that are always there, in the order they read.
    private static let standing: [LibraryScope] = [.all, .favourites, .lastSevenDays]

    var body: some View {
        List(selection: selection) {
            Section("Library") {
                ForEach(Self.standing, id: \.self) { scope in
                    LibrarySourceRow(scope: scope)
                }
            }
            Section("Models") {
                ForEach(ModelCatalog.all) { model in
                    ModelSourceRow(model: model)
                }
            }
            TagSources()
            AlbumSources(edit: $albumEdit)
        }
        .listStyle(.sidebar)
    }

    /// The list's selection is the scope, which is not optional, so an empty selection is read
    /// as "no change" rather than as a scope of nothing. Choosing one shows the library: on the
    /// canvas these rows would otherwise change a query nothing on screen is drawn from.
    private var selection: Binding<LibraryScope?> {
        Binding(
            get: { workspace.query.scope },
            set: { if let scope = $0 { workspace.show(scope: scope) } }
        )
    }
}

#Preview("Sources") {
    @Previewable @State var albumEdit: AlbumEdit?
    SidebarSources(albumEdit: $albumEdit)
        .frame(width: 280, height: 560)
        .environment(WorkspaceSelection(pane: .library))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}

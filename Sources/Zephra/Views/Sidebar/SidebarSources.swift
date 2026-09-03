import SwiftUI
import ZephraCore
import ZephraEngine

/// Where to look: the standing collections, one row per model, the tags in use, and then
/// whichever of Today and Albums belongs to the pane that is showing.
///
/// The last section changes with the pane because the two answer different questions. On the
/// canvas the sidebar is a way back to what was just made, so it shows today's images. In the
/// library the pane is already showing them at full size, so the sidebar stops repeating itself
/// and does the filing instead.
struct SidebarSources: View {
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
            switch workspace.pane {
            case .canvas: TodaySection()
            case .library: AlbumSources()
            }
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

#Preview("Sources, library pane") {
    SidebarSources()
        .frame(width: 280, height: 560)
        .environment(WorkspaceSelection(pane: .library))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}

#Preview("Sources, canvas pane") {
    SidebarSources()
        .frame(width: 280, height: 560)
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}

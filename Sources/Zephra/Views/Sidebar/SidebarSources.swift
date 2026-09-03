import SwiftUI
import ZephraCore
import ZephraEngine

/// Where to look: the standing collections, then one row per model.
///
/// The counts are zeroes until the library index exists. They are drawn now rather than left
/// out so the row's shape is settled: a number that appears later must not move the title.
struct SidebarSources: View {
    @Environment(WorkspaceSelection.self) private var workspace

    /// The collections that are always there, in the order they read.
    private static let standing: [LibraryScope] = [.all, .favourites, .lastSevenDays]

    var body: some View {
        List(selection: selection) {
            Section("Library") {
                ForEach(Self.standing, id: \.self) { scope in
                    HStack(spacing: 8) {
                        Label(scope.title, systemImage: scope.systemImage)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        CountBadge(0)
                    }
                    .frame(height: ZephraChrome.sidebarRowHeight)
                    .tag(scope)
                }
            }
            Section("Models") {
                ForEach(ModelCatalog.all) { model in
                    ModelSourceRow(model: model)
                }
            }
            TodaySection()
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
    SidebarSources()
        .frame(width: 280, height: 460)
        .environment(WorkspaceSelection(pane: .library))
}

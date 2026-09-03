import SwiftUI
import ZephraCore
import ZephraEngine

/// The two or three narrowings worth reaching for without opening a menu: everything,
/// favourites, and one chip per model.
///
/// A model chip is named in full rather than by display name, because two of the catalog's
/// entries are the same model at different precisions and "Z-Image Turbo" twice would be a
/// choice nobody could make.
struct ScopeChips: View {
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        WrappingHStack {
            chip("All", isSelected: workspace.query.scope == .all && workspace.query.modelID == nil) {
                workspace.query.scope = .all
                workspace.query.modelID = nil
            }
            chip(LibraryScope.favourites.title, isSelected: workspace.query.scope == .favourites) {
                workspace.query.scope = .favourites
                workspace.query.modelID = nil
            }
            ForEach(ModelCatalog.all) { model in
                chip(model.fullName, isSelected: workspace.query.modelID == model.id) {
                    workspace.query.modelID = workspace.query.modelID == model.id ? nil : model.id
                }
            }
        }
    }

    private func chip(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Chip(title, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Chips") {
    ScopeChips()
        .padding()
        .frame(width: 280)
        .environment(WorkspaceSelection(pane: .canvas))
}

#Preview("Narrowed to a model") {
    ScopeChips()
        .padding()
        .frame(width: 280)
        .environment(WorkspaceSelection(
            pane: .library,
            query: LibraryQuery(modelID: ModelCatalog.default.id)
        ))
}

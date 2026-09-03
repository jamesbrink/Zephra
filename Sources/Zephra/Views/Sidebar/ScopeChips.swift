import SwiftUI
import ZephraCore
import ZephraEngine

/// The two or three narrowings worth reaching for without opening a menu: everything,
/// favourites, and one chip per model.
///
/// A model is named by its display name alone unless another catalog entry shares it, when
/// both take their variant as well. Today that reads "Z-Image Turbo · 8-bit", "Z-Image Turbo ·
/// 4-bit", "Qwen-Image 2512" — the shortest names that can still be told apart.
struct ScopeChips: View {
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        WrappingHStack {
            chip("All", isSelected: workspace.query.scope == .all && workspace.query.modelID == nil) {
                // Widening is not a reason to change pane: this is the way back from a chip
                // pressed by mistake, and it should leave you where you are.
                workspace.query.scope = .all
                workspace.query.modelID = nil
            }
            chip(LibraryScope.favourites.title, isSelected: workspace.query.scope == .favourites) {
                workspace.query.modelID = nil
                workspace.show(scope: .favourites)
            }
            ForEach(ModelCatalog.all) { model in
                chip(Self.title(of: model), isSelected: workspace.query.modelID == model.id) {
                    if workspace.query.modelID == model.id {
                        workspace.query.modelID = nil
                    } else {
                        workspace.show(modelID: model.id)
                    }
                }
            }
        }
    }

    /// A model's shortest unambiguous name: its display name, or its full name when another
    /// entry in the catalog goes by the same display name.
    private static func title(of model: ModelDescriptor) -> String {
        let sharers = ModelCatalog.all.count { $0.displayName == model.displayName }
        return sharers > 1 ? model.fullName : model.displayName
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

import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// The two narrowings worth reaching for without moving the eye: everything, and favourites.
///
/// Deliberately not one chip per model, which is what the mock drew when the catalog held
/// three. Five entries wrap this row onto five lines and push the sources below it off the
/// screen, and the Models section a few rows down already lists every one of them with its
/// count. A chip row that grows with the catalog is a chip row that eventually swallows the
/// sidebar, so this one is fixed at the two scopes that are about the pictures rather than
/// about which model made them.
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

#Preview("Narrowed to favorites") {
    ScopeChips()
        .padding()
        .frame(width: 280)
        .environment(WorkspaceSelection(
            pane: .library,
            query: LibraryQuery(scope: .favourites)
        ))
}

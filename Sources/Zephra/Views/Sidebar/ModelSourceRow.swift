import SwiftUI
import ZephraCore
import ZephraEngine

/// One model in the sidebar's Models section: its colour, its name, and how many images it
/// made. Pressing it narrows the library to that model; pressing it again widens it back.
///
/// A button rather than a selectable row, because the list's selection is the scope and a
/// model is a filter over whichever scope is showing, not a scope of its own.
struct ModelSourceRow: View {
    /// The model this row stands for.
    let model: ModelDescriptor

    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        Button {
            if isSelected {
                workspace.query.modelID = nil
            } else {
                workspace.show(modelID: model.id)
            }
        } label: {
            HStack(spacing: 8) {
                ModelDot(model.id)
                Text(model.fullName)
                    .lineLimit(1)
                Spacer(minLength: 8)
                CountBadge(index.counts.perModel[model.id] ?? 0)
            }
            .frame(height: ZephraChrome.sidebarRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            Rectangle()
                .fill(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isSelected: Bool { workspace.query.modelID == model.id }
}

#Preview("Model row") {
    List {
        ForEach(ModelCatalog.all) { model in
            ModelSourceRow(model: model)
        }
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 160)
    .environment(WorkspaceSelection(pane: .library))
    .environment(LibraryIndex.preview(count: 38))
}

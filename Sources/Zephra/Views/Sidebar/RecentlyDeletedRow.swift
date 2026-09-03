import SwiftUI
import ZephraEngine

/// Pinned to the bottom of the sidebar, below everything that scrolls: the images that were
/// deleted and can still be had back. It is at the bottom because that is where it belongs in
/// the mind, not because it is unimportant.
struct RecentlyDeletedRow: View {
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        Button {
            workspace.show(scope: .recentlyDeleted)
        } label: {
            HStack(spacing: 8) {
                Label(
                    LibraryScope.recentlyDeleted.title,
                    systemImage: LibraryScope.recentlyDeleted.systemImage
                )
                .lineLimit(1)
                Spacer(minLength: 8)
                CountBadge(index.counts.recentlyDeleted)
            }
            .font(.callout)
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isSelected: Bool { workspace.query.scope == .recentlyDeleted }
}

#Preview("Recently deleted") {
    RecentlyDeletedRow()
        .frame(width: 280)
        .environment(WorkspaceSelection(pane: .library))
        .environment(LibraryIndex.preview(count: 38))
}

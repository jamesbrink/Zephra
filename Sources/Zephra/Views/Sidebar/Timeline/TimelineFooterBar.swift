import SwiftUI
import ZephraEngine

/// Pinned to the foot of the canvas sidebar: the way to the library, with how much of today is
/// waiting there.
///
/// A bar rather than a link at the end of the list, because a link that appears once there is
/// something to show is also a link that vanishes, and a foot that comes and goes is not a foot.
/// The same shape as `NewAlbumBar` on the other pane, so the sidebar ends the same way whichever
/// it is showing.
struct TimelineFooterBar: View {
    /// How many pictures today has produced.
    let count: Int

    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        Button {
            // Coming to the library from the canvas means "show me everything": a view still
            // narrowed by yesterday's search would look like an empty library.
            workspace.query = LibraryQuery()
            workspace.pane = .library
        } label: {
            HStack(spacing: 8) {
                Label("Today in Library", systemImage: "photo.on.rectangle.angled")
                    .lineLimit(1)
                Spacer(minLength: 8)
                CountBadge(count)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .help("Show today's images in the Library")
    }
}

#Preview("Footer") {
    TimelineFooterBar(count: 7)
        .frame(width: 280)
        .environment(WorkspaceSelection(pane: .canvas))
}

import SwiftUI

/// How big the images in the grid are drawn, from a wall of them to a handful.
///
/// Continuous, though only four sizes are ever baked: the grid lays itself out at whatever the
/// slider says, and the cache rounds up to the next bucket. Four buckets are indistinguishable
/// from a smooth zoom to look at, and are the difference between four files per image and two
/// hundred.
///
/// Declared from `WorkspaceToolbar`, the leading item of its trailing group, the same way
/// `LibrarySortMenu` and `ModelMenu` show only on one pane: the toolbar's leading side is only
/// the pane picker on both panes, so keeping the library's own items — zoom, sort, inspector,
/// settings — and the canvas's — model, inspector, settings — the same shape is
/// `WorkspaceToolbar`'s to do, not a thing an item declared inside `LibraryPane`'s own column
/// could do on its own. Hidden while the library viewer is up besides: a picture already fitted
/// to the pane has no grid to size.
struct LibraryZoomSlider: View {
    @Environment(WorkspaceSelection.self) private var workspace

    @AppStorage(AppSettings.libraryThumbnailEdge)
    private var edge = AppSettings.initialLibraryThumbnailEdge

    var body: some View {
        if workspace.pane == .library && workspace.viewing == nil {
            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $edge, in: AppSettings.libraryThumbnailEdgeBounds)
                    .controlSize(.small)
                    .frame(width: 110)
                    .accessibilityLabel("Thumbnail size")
                    .accessibilityValue("\(Int(edge)) points")
                Image(systemName: "photo")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .help("Thumbnail size")
        }
    }
}

#Preview("Zoom") {
    LibraryZoomSlider()
        .padding(20)
        .environment(WorkspaceSelection(pane: .library))
}

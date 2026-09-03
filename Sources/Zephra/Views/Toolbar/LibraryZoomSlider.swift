import SwiftUI

/// How big the images in the grid are drawn, from a wall of them to a handful.
///
/// Continuous, though only four sizes are ever baked: the grid lays itself out at whatever the
/// slider says, and the cache rounds up to the next bucket. Four buckets are indistinguishable
/// from a smooth zoom to look at, and are the difference between four files per image and two
/// hundred.
///
/// Declared as a toolbar item from `LibraryPane` rather than from `WorkspaceToolbar`: an item
/// declared inside a column lands in that column's own toolbar section and disappears with the
/// pane on its own, without a `workspace.pane == .library` check like the items in
/// `WorkspaceToolbar` need. `.navigation` is where it sits — before the window title on macOS
/// 26, matching where Photos puts its own zoom slider.
struct LibraryZoomSlider: View {
    @AppStorage(AppSettings.libraryThumbnailEdge)
    private var edge = AppSettings.initialLibraryThumbnailEdge

    var body: some View {
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

#Preview("Zoom") {
    LibraryZoomSlider()
        .padding(20)
}

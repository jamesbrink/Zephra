import SwiftUI

/// How big the images in the grid are drawn, from a wall of them to a handful.
///
/// Continuous, though only four sizes are ever baked: the grid lays itself out at whatever the
/// slider says, and the cache rounds up to the next bucket. Four buckets are indistinguishable
/// from a smooth zoom to look at, and are the difference between four files per image and two
/// hundred.
struct ThumbnailSizeSlider: View {
    @AppStorage(AppSettings.libraryThumbnailEdge)
    private var edge = AppSettings.initialLibraryThumbnailEdge

    var body: some View {
        HStack(spacing: 8) {
            Text("Size")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $edge, in: AppSettings.libraryThumbnailEdgeBounds)
                .controlSize(.mini)
                .frame(width: 90)
                .accessibilityLabel("Thumbnail size")
                .accessibilityValue("\(Int(edge)) points")
        }
    }
}

#Preview("Size") {
    ThumbnailSizeSlider()
        .padding(20)
}

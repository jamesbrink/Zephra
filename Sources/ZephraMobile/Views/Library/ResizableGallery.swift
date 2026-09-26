import SwiftUI

/// Gesture and accessible menu own density; the grid keeps stable media identities.
struct ResizableGallery: View {
    @AppStorage(MobileSettings.galleryColumns, store: MobileSettings.store) private var columns = 3
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var start: Int?
    var body: some View {
        LibraryGrid()
            .environment(\.galleryColumns, typeSize.isAccessibilitySize ? 1 : min(6, max(1, columns)))
            .simultaneousGesture(MagnifyGesture()
                .onChanged { value in
                    if start == nil { start = columns }
                    columns = GalleryDensity.columns(start: start ?? columns, magnification: value.magnification)
                }
                .onEnded { _ in start = nil })
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Thumbnail Size", systemImage: "square.grid.3x3") {
                        Button("Larger Thumbnails", systemImage: "plus.magnifyingglass") { columns = max(1, columns - 1) }
                            .disabled(columns <= 1)
                        Button("Smaller Thumbnails", systemImage: "minus.magnifyingglass") { columns = min(6, columns + 1) }
                            .disabled(columns >= 6)
                        Button("Reset Thumbnail Size") { columns = 3 }
                    }
                    .accessibilityHint("Pinch the gallery to change thumbnail size")
                    .disabled(typeSize.isAccessibilitySize)
                }
            }
    }
}

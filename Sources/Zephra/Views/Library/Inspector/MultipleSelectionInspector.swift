import SwiftUI
import ZephraEngine

/// Several images at once: what they are, what they have in common, and what can be done to all
/// of them.
///
/// A fact that differs across the selection reads "Multiple" rather than being left blank or
/// being shown for the first image, both of which would be a claim about images that do not
/// agree with it.
struct MultipleSelectionInspector: View {
    /// The images chosen, in the order the grid is showing them.
    let items: [LibraryItem]

    @Environment(ThumbnailCache.self) private var thumbnails

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StackedThumbnails(items: items)
                    .environment(
                        \.libraryThumbnails, LibraryThumbnails(cache: thumbnails, size: .large)
                    )
                Text("\(items.count) images selected")
                    .font(.headline)
                    .monospacedDigit()
                SharedFactsView(items: items)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Several images") {
    MultipleSelectionInspector(items: Array(LibraryIndex.preview(count: 6).items.prefix(4)))
        .frame(width: 320, height: 620)
        .environment(ThumbnailCache())
        .environment(LibraryIndex.preview(count: 6))
        .environment(GenerationStore.preview(state: .ready))
}

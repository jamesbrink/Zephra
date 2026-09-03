import SwiftUI
import ZephraEngine

/// One image, at length: the picture, what it was asked for, and how it was made.
///
/// The prompt is set in a serif face and at reading size, because it is the one thing on this
/// column that is prose rather than data. Everything below it is a table, and looks like one.
struct SingleImageInspector: View {
    /// The image being looked at.
    let item: LibraryItem

    @Environment(ThumbnailCache.self) private var thumbnails

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LibraryThumbnail(item: item)
                    .clipShape(
                        RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous)
                    )
                    .environment(
                        \.libraryThumbnails, LibraryThumbnails(cache: thumbnails, size: .extraLarge)
                    )
                if !item.prompt.isEmpty {
                    Text(item.prompt)
                        .font(.callout)
                        .fontDesign(.serif)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ImageFactsView(item: item)
                InspectorActions(item: item)
            }
            .padding(18)
        }
    }
}

#Preview("One image") {
    SingleImageInspector(item: LibraryIndex.preview(count: 1).items[0])
        .frame(width: 320, height: 620)
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}

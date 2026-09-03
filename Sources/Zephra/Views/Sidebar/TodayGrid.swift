import SwiftUI
import ZephraEngine

/// Four of today's images, two by two, in one row of the sidebar's list.
///
/// One list row rather than a row per image, because the grid is a single object to scroll
/// past and a `List` that thought it held four rows would put separators through it.
///
/// A press opens the image on the canvas without adopting its settings, which is what
/// `GenerationStore.open(_:)` is for: coming back to look at something must not quietly
/// replace the prompt being written.
struct TodayGrid: View {
    /// The images to show, newest first.
    let items: [LibraryItem]

    @Environment(GenerationStore.self) private var store
    @Environment(ThumbnailCache.self) private var thumbnails

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
            ForEach(items) { item in
                Button {
                    Task { await store.open(item) }
                } label: {
                    LibraryThumbnail(item: item)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            if isShowing(item) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.prompt.isEmpty ? item.fileName : item.prompt)
                .accessibilityAddTraits(isShowing(item) ? .isSelected : [])
            }
        }
        .environment(\.libraryThumbnails, LibraryThumbnails(cache: thumbnails, size: .small))
        .padding(.vertical, 2)
    }

    /// Whether this is the image the canvas is showing, which gets a ring so the sidebar and
    /// the canvas agree about where you are.
    private func isShowing(_ item: LibraryItem) -> Bool {
        store.current?.fileURL?.standardizedFileURL == item.url
    }
}

#Preview("Today's four") {
    List {
        TodayGrid(items: Array(PreviewImages.library(count: 8).items.prefix(4)))
            .listRowBackground(Color.clear)
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 200)
    .environment(ThumbnailCache())
    .environment(GenerationStore.preview(state: .ready))
}

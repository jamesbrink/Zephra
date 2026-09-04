import AppKit
import SwiftUI
import ZephraEngine

/// One library image, letterboxed full size, with `LibraryViewerBar` over the top.
///
/// The thumbnail already baked for the grid stands in until the full-resolution bytes are
/// decoded, off the main actor: a library picture can be a good deal larger than anything the
/// grid ever asks `LibraryThumbnail` for, and nothing in this app decodes on the main actor.
/// `item` changing — which happens every time a step lands on a new one, `LibraryPane` handing
/// down a new value rather than this view moving itself — is what restarts the decode; `.task`
/// keyed on its id is what notices.
///
/// `LibraryViewerNavigation` carries Escape, the arrow keys, and the double-click that close or
/// step the viewer; it is a modifier of its own, the same shape as `LibraryOpenCommand`, rather
/// than more stored properties here. Which selection to keep in step as it steps is decided by
/// `LibraryPane`, not by anything below it, so neither that modifier nor this view needs to
/// hold one — the context menu still wants it, and reads it the way `LibraryInspector` already
/// does, through the value `LibraryPane` publishes.
struct LibraryViewer: View {
    /// The image to show.
    let item: LibraryItem

    @FocusedValue(\.librarySelection) private var selection
    @State private var image: NSImage?

    var body: some View {
        picture
            .modifier(LibraryViewerNavigation())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.canvasBackground)
            .safeAreaInset(edge: .top, spacing: 0) { LibraryViewerBar() }
            .contextMenu { LibraryItemMenu(items: [item], selection: selection) }
            .draggable(item)
            .task(id: item.id) { await decode() }
    }

    @ViewBuilder
    private var picture: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .accessibilityLabel(item.prompt.isEmpty ? item.fileName : item.prompt)
        } else {
            LibraryThumbnail(item: item)
                .accessibilityHidden(true)
        }
    }

    /// Reads the file off the main actor. `NSImage(contentsOf:)` rather than `ImageCache`,
    /// which is keyed by a session's own `GeneratedImage` identity and knows nothing about a
    /// file the library, not this session, produced.
    private func decode() async {
        image = nil
        let url = item.url
        image = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
    }
}

#Preview("Viewer") {
    let index = PreviewImages.library(count: 8)
    return LibraryViewer(item: index.items[0])
        .frame(width: 900, height: 700)
        .environment(\.libraryThumbnails, LibraryThumbnails(cache: ThumbnailCache(), edge: 168))
        .environment(WorkspaceSelection(pane: .library))
        .environment(index)
        .environment(GenerationStore.preview(state: .ready))
}

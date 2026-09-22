import AppKit
import SwiftUI
import ZephraEngine
import ZephraStyle

/// One library image, letterboxed full size, with `LibraryViewerBar` above it.
///
/// The bar is stacked above the picture rather than laid over it as a safe-area inset, so the
/// picture is fitted to the height it actually has; inset, it was laid out for the pane's
/// whole height and its top ran under the bar.
///
/// `ViewerPlaceholder` — the grid's thumbnail at the picture's own aspect — stands in until
/// the full-resolution bytes are decoded, off the main actor: a library picture can be a good
/// deal larger than anything the grid ever asks `LibraryThumbnail` for, and nothing in this
/// app decodes on the main actor.
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
        VStack(spacing: 0) {
            LibraryViewerBar()
            picture
                .modifier(LibraryViewerNavigation())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contextMenu { LibraryItemMenu(items: [item], selection: selection) }
                .draggable(item)
        }
        .background(Color.canvasBackground)
        // Keyed by what the scan fingerprints the file by, not by its path alone: an id
        // is a path, and a picture rewritten in place keeps its path while its pixels
        // change, which the index notices and the viewer would otherwise not.
        .task(id: "\(item.id)|\(item.fileSize)|\(item.contentModifiedAt.timeIntervalSince1970)") {
            // A clip's poster is never drawn here; the player is.
            if item.videoURL == nil { await decode() }
        }
    }

    @ViewBuilder
    private var picture: some View {
        if item.videoURL != nil {
            LibraryViewerClip(item: item)
        } else if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                // Behind the picture's own rectangle rather than behind the pane: `aspectRatio`
                // sizes this view to the fitted picture, so the letterbox stays the canvas's
                // colour and the checkerboard is exactly as big as the picture.
                .background { if item.hasAlpha { TransparencyGround() } }
                .accessibilityLabel(item.prompt.isEmpty ? item.fileName : item.prompt)
        } else {
            ViewerPlaceholder(item: item)
        }
    }

    /// Reads the file off the main actor. `NSImage(contentsOf:)` rather than `ImageCache`,
    /// which is keyed by a session's own `GeneratedImage` identity and knows nothing about a
    /// file the library, not this session, produced.
    private func decode() async {
        image = nil
        let url = item.url
        let decoded = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
        // Stepping on cancels this task but not the detached decode; a slow picture that
        // finishes after a newer one must not paint over it.
        guard !Task.isCancelled else { return }
        image = decoded
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

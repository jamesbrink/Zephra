import SwiftUI
import ZephraEngine

/// The viewer's picture when the item is a clip: the player over its MP4, fitted the way the
/// picture would be, holding still while the model works.
///
/// A view of its own so `LibraryViewer` keeps to its three stored properties: this one is
/// the one that has to watch the store.
struct LibraryViewerClip: View {
    /// The clip's poster item.
    let item: LibraryItem
    @Environment(GenerationStore.self) private var store

    var body: some View {
        if let clip = item.videoURL {
            ClipPlayerView(url: clip, paused: store.running != nil)
                .aspectRatio(item.size.aspectRatio, contentMode: .fit)
                .accessibilityLabel(item.prompt.isEmpty ? item.fileName : item.prompt)
        }
    }
}

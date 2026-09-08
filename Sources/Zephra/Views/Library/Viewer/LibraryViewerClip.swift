import SwiftUI
import ZephraEngine

/// The viewer's picture when the item is a clip: the player over its MP4, fitted the way the
/// picture would be, playing whether or not the model is working.
///
/// A view of its own so the viewer's `picture` reads as one line per kind of item.
struct LibraryViewerClip: View {
    /// The clip's poster item.
    let item: LibraryItem

    var body: some View {
        if let clip = item.videoURL {
            ClipPlayerView(url: clip)
                .aspectRatio(item.size.aspectRatio, contentMode: .fit)
                .accessibilityLabel(item.prompt.isEmpty ? item.fileName : item.prompt)
        }
    }
}

import AppKit
import SwiftUI
import ZephraEngine

/// The 40 pt thumbnail `ReferenceFactsRow` shows beside its facts, split out so the row itself
/// does not have to hold the cache or the decode's own state.
///
/// The thumbnail is never read on the main actor. `LibraryItem.referenceImage` is a synchronous
/// whole-file read, so a library source runs it inside a detached task started from
/// `.task(id:)`; a picture the session still holds in memory already has its bytes at hand and
/// only needs the decode, which `ImageCache.referenceThumbnail` does off the main actor either
/// way.
struct ReferenceSourceThumbnail: View {
    /// The source picture whose bytes make the thumbnail.
    let source: ReferenceFactsRow.Source

    @Environment(ImageCache.self) private var cache
    @State private var thumbnail: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: ZephraChrome.fieldRadius, style: .continuous)
            .fill(.quaternary)
            .frame(width: 40, height: 40)
            .overlay {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(
                            RoundedRectangle(cornerRadius: ZephraChrome.fieldRadius, style: .continuous)
                        )
                }
            }
            .task(id: source) { await loadThumbnail() }
    }

    /// Puts the old picture down first and checks for cancellation after every await: the
    /// selection can move while a read is in flight, `.task(id:)` cancels this task but not
    /// the detached read or the decode it awaits, and a slow source landing after a quick one
    /// would put the wrong picture beside the new selection's facts.
    private func loadThumbnail() async {
        thumbnail = nil
        let png: Data?
        switch source {
        case .library(let item, _):
            png = await Task.detached(priority: .userInitiated) { item.referenceImage }.value
        case .bytes(let data, _):
            png = data
        }
        guard !Task.isCancelled, let png else { return }
        let made = await cache.referenceThumbnail(png)
        guard !Task.isCancelled else { return }
        thumbnail = made
    }
}

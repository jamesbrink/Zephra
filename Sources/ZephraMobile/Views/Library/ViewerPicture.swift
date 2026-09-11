import SwiftUI
import UIKit

/// One picture at its full size, or one clip playing.
///
/// Three things arrive in order, and the view shows whichever it has: the cell's thumbnail,
/// which is already on the phone and appears instantly; the larger thumbnail; and the file
/// itself. So a picture opened in a tunnel is the small one blown up rather than a grey
/// rectangle, and a picture opened on the sofa sharpens twice within a second.
///
/// Each of the three is decoded off the main actor before it is shown: the file is megabytes,
/// and decoding it where the interface runs is a frozen viewer somebody is pinching.
///
/// A clip skips all of that and asks for its MP4, because a poster is not a clip.
struct ViewerPicture: View {
    /// The picture to show.
    let entry: CachedEntry

    @Environment(LibraryCatalog.self) private var catalog
    /// What is on screen so far: nothing, a picture, or a clip.
    @State private var shown: ViewerPictureState = .waiting

    var body: some View {
        Group {
            switch shown {
            case .waiting:
                ProgressView().tint(.white)
            case .picture(let image):
                ZoomablePicture(picture: image)
            case .clip(let url):
                ClipPlayerView(url: url, showsControls: true)
            case .unavailable(let reason):
                ContentUnavailableView("Not on This Phone", systemImage: "wifi.slash",
                    description: Text(reason))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: entry.fileName) { await load() }
    }

    /// The thumbnail first, then the larger one, then the file — each shown as it lands.
    private func load() async {
        if let small = await catalog.thumbnail(for: entry), case .waiting = shown {
            await show(small)
        }
        if entry.isVideo {
            do { shown = .clip(try await catalog.file(for: entry)) } catch { fell(to: error) }
            return
        }
        if let large = await catalog.thumbnail(for: entry, pixels: ThumbnailStore.viewerPixels) {
            await show(large)
        }
        do {
            let url = try await catalog.file(for: entry)
            guard let picture = await DecodedPicture.contentsOf(url) else { return }
            shown = .picture(picture)
        } catch {
            fell(to: error)
        }
    }

    /// Puts one set of bytes on screen, decoded off the main actor.
    private func show(_ data: Data) async {
        guard let picture = await DecodedPicture.from(data) else { return }
        shown = .picture(picture)
    }

    /// A failure that leaves a thumbnail on screen is not worth reporting: what is there is a
    /// picture, only a smaller one. A failure with nothing on screen is.
    ///
    /// The cache's own failures carry sentences and are shown as they are. Everything else is
    /// a link that would not answer, and `LinkClientError`'s own description is a Swift error
    /// number — nothing to put in front of somebody who wanted to look at a picture.
    private func fell(to error: any Error) {
        guard case .waiting = shown else { return }
        let sentence = (error as? LibraryCacheError)?.errorDescription
            ?? "Your Mac could not send this one. It comes down the next time it is in reach."
        shown = .unavailable(sentence)
    }
}

/// How much of one picture has arrived.
enum ViewerPictureState {
    /// Nothing yet.
    case waiting
    /// A still picture: a thumbnail at first, the file in the end.
    case picture(UIImage)
    /// A clip, as a file on this phone.
    case clip(URL)
    /// Nothing could be got, in the words to show.
    case unavailable(String)
}

import SwiftUI

/// One picture at its full size, or one clip playing.
///
/// Three things arrive in order, and the view shows whichever it has: the cell's thumbnail,
/// which is already on the phone and appears instantly; the larger thumbnail; and the file
/// itself. So a picture opened in a tunnel is the small one blown up rather than a grey
/// rectangle, and a picture opened on the sofa sharpens twice within a second.
///
/// A clip skips all of that and asks for its MP4, because a poster is not a clip.
struct ItemPicture: View {
    /// The picture to show.
    let entry: CachedEntry

    @Environment(LibraryCatalog.self) private var catalog
    /// What is on screen so far: nothing, a thumbnail, or the file.
    @State private var shown: ItemPictureState = .waiting

    var body: some View {
        Group {
            switch shown {
            case .waiting:
                ProgressView().tint(.white)
            case .picture(let data):
                ZoomablePicture(data: data)
            case .clip(let url):
                ClipPlayer(url: url)
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
            shown = .picture(small)
        }
        if entry.isVideo {
            do { shown = .clip(try await catalog.file(for: entry)) } catch { fell(to: error) }
            return
        }
        if let large = await catalog.thumbnail(for: entry, pixels: ThumbnailStore.viewerPixels) {
            shown = .picture(large)
        }
        do { shown = .picture(try Data(contentsOf: await catalog.file(for: entry))) } catch {
            fell(to: error)
        }
    }

    /// A failure that leaves a thumbnail on screen is not worth reporting: what is there is a
    /// picture, only a smaller one. A failure with nothing on screen is.
    private func fell(to error: any Error) {
        guard case .waiting = shown else { return }
        shown = .unavailable(error.localizedDescription)
    }
}

/// How much of one picture has arrived.
enum ItemPictureState {
    /// Nothing yet.
    case waiting
    /// Some bytes of a still picture: a thumbnail at first, the file in the end.
    case picture(Data)
    /// A clip, as a file on this phone.
    case clip(URL)
    /// Nothing could be got, in the words to show.
    case unavailable(String)
}

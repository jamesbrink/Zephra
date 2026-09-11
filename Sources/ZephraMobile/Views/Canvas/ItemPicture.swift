import SwiftUI
import UIKit
import ZephraStyle

/// One of the Mac's pictures, at the size the screen has room for.
///
/// The bytes come through `LibraryCatalog`, which is the one cache on this phone: the file the
/// library already fetched is the file the canvas draws, and the file the canvas fetches is
/// already here when the library opens it. A picture therefore crosses the link once for both
/// surfaces, which matters when the link is a relay on the far side of the world.
///
/// The decode is off the main actor, because a full-size PNG is tens of milliseconds and that
/// is a dropped frame. A fetch that will not arrive says so rather than leaving a blank square:
/// the Mac gone, or a frozen preview with no road under it, is a fact worth a sentence.
struct ItemPicture: View {
    /// The file's name in the Mac's library, which is its identity everywhere in the protocol.
    let name: String
    @Environment(LibraryCatalog.self) private var catalog
    @State private var phase = FetchPhase<UIImage>.fetching

    var body: some View {
        Group {
            if let picture = phase.value {
                Image(uiImage: picture)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: ZephraChrome.cardRadius, style: .continuous))
            } else {
                PictureUnavailable(isFetching: isFetching)
            }
        }
        .task(id: name) { await load() }
        .accessibilityLabel("The newest picture")
    }

    private var isFetching: Bool {
        if case .fetching = phase { return true }
        return false
    }

    private func load() async {
        phase = .fetching
        guard let data = await catalog.picture(named: name),
            let picture = await DecodedPicture.from(data)
        else {
            phase = .missing
            return
        }
        phase = .ready(picture)
    }
}

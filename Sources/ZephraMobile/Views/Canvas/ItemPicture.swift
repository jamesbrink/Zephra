import SwiftUI
import UIKit
import ZephraLinkClient
import ZephraStyle

/// One of the Mac's pictures, at the size the screen has room for.
///
/// The bytes are the file itself, fetched once and kept in `PictureCache`: a picture crosses
/// the link once, so walking to the library and back does not fetch a megabyte again over what
/// may be a relay. The decode happens inside the cache's actor, off the main actor, because a
/// full-size PNG is tens of milliseconds and that is a dropped frame in the middle of a scroll.
///
/// A fetch that will not arrive says so rather than leaving a blank square: the Mac gone, or a
/// frozen preview with no road under it, is a fact worth a sentence.
struct ItemPicture: View {
    /// The file's name in the Mac's library, which is its identity everywhere in the protocol.
    let name: String
    @Environment(LinkClient.self) private var client
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
        if let held = await PictureCache.shared.picture(named: name) {
            phase = .ready(held)
            return
        }
        phase = .fetching
        guard let data = try? await client.file(name: name),
            let picture = await PictureCache.shared.store(data, for: name)
        else {
            phase = .missing
            return
        }
        phase = .ready(picture)
    }
}

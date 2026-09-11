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
/// Until it lands there is a quiet rectangle rather than a spinner: a fetch that fails — the
/// Mac gone, or a frozen preview with no road under it — leaves a shape where the picture
/// would be, and a spinner there would promise something that is not coming.
struct ItemPicture: View {
    /// The file's name in the Mac's library, which is its identity everywhere in the protocol.
    let name: String
    @Environment(LinkClient.self) private var client
    @State private var picture: UIImage?

    var body: some View {
        Group {
            if let picture {
                Image(uiImage: picture)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous)
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous))
        .task(id: name) { await load() }
        .accessibilityLabel("The newest picture")
    }

    private func load() async {
        if let held = await PictureCache.shared.picture(named: name) {
            picture = held
            return
        }
        picture = nil
        guard let data = try? await client.file(name: name) else { return }
        picture = await PictureCache.shared.store(data, for: name)
    }
}

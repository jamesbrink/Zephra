import SwiftUI
import UIKit
import ZephraLinkClient
import ZephraStyle

/// One square of the reference picker: a thumbnail the Mac baked, at the size the grid draws.
///
/// A thumbnail and not the picture: a grid of full-size PNGs would be tens of megabytes over
/// what may be a relay, for squares a hundred pixels across. The picture itself is fetched
/// only for the one that is picked.
struct LibraryThumbnail: View {
    /// The file's name in the Mac's library.
    let name: String
    @Environment(LinkClient.self) private var client
    @State private var picture: UIImage?

    /// How many pixels a square is asked for on its long edge: twice the grid's cell, so it is
    /// sharp on a phone's screen and still small on the wire.
    private static let pixels = 256

    var body: some View {
        RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous)
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let picture {
                    Image(uiImage: picture)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipShape(
                RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous)
            )
            .task(id: name) {
                guard let data = try? await client.thumbnail(name: name, pixels: Self.pixels)
                else { return }
                picture = await Task.detached { UIImage(data: data) }.value
            }
            .accessibilityLabel(name)
    }
}

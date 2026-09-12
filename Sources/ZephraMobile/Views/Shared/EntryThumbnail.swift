import SwiftUI
import UIKit

/// One picture at thumbnail size, from the cache if it is there and from the Mac if it is not.
///
/// The one square in the app: the library's grid, the reference picker's grid and a run's strip
/// all draw this, so a picture fetched on one surface is on the phone for the others and there
/// is one rule for what a missing one looks like. A thumbnail and never the picture — a grid of
/// full-size PNGs would be tens of megabytes over what may be a relay, for squares a hundred
/// points across.
///
/// The fetch is in `.task`, which SwiftUI cancels when the square scrolls away, so a fast flick
/// through a thousand pictures asks the Mac for the handful it stopped on. Keyed on the entry's
/// version, because that is what changes when the Mac rewrites the file, and on the Mac being
/// in reach, because a square that could not be fetched during a drop would otherwise stay grey
/// until the view was built again — which for a cell somebody is looking at means until they
/// scroll it away and back.
struct EntryThumbnail: View {
    /// The picture this square shows.
    let entry: CachedEntry

    @Environment(LibraryCatalog.self) private var catalog
    /// The thumbnail once it is here, under the version it arrived for.
    @State private var picture: Fetched<UIImage>?

    var body: some View {
        Color.clear
            .overlay {
                if let picture = picture?.value {
                    Image(uiImage: picture)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .task(id: FetchKey(name: entry.version, isLive: catalog.isLive)) { await load() }
    }

    /// The thumbnail, unless the one already here is for this very version of this picture.
    private func load() async {
        guard picture?.matches(entry.version) != true else { return }
        guard let data = await catalog.thumbnail(for: entry),
            let decoded = await DecodedPicture.from(data)
        else { return }
        picture = Fetched(name: entry.version, value: decoded)
    }
}

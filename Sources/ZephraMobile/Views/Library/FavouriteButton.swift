import SwiftUI

/// "Add to Favorites", or "Remove from Favorites": the Mac's own two words, since the
/// annotation lives in the picture's PNG and this is asking the Mac to rewrite it.
///
/// Greyed while the Mac cannot be reached. The star is the Mac's to set and the phone's copy
/// of an entry is a guess until the next sync brings the file's new fingerprint back, so
/// filling one in offline would be a lie about a file this phone cannot touch.
struct FavouriteButton: View {
    /// The picture to mark.
    let entry: CachedEntry

    @Environment(LibraryCatalog.self) private var catalog

    var body: some View {
        Button(title, systemImage: entry.isFavourite ? "star.slash" : "star") {
            Task { await catalog.setFavourite([entry.id], on: !entry.isFavourite) }
        }
        .disabled(!catalog.isLive(for: entry))
    }

    private var title: String {
        entry.isFavourite ? "Remove from Favorites" : "Add to Favorites"
    }
}

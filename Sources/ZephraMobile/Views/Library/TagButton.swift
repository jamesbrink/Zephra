import SwiftUI

/// "Tag…": the ellipsis because it raises a sheet, as it does on the Mac.
///
/// The sheet belongs to whichever surface is presenting, so this only asks — see
/// `LibraryRequests`. Greyed with the Mac out of reach, for `FavouriteButton`'s reason: the
/// tags are in the picture's own PNG and only the Mac writes them.
struct TagButton: View {
    /// The picture to tag.
    let entry: CachedEntry

    @Environment(LibraryCatalog.self) private var catalog
    @Environment(\.tagLibraryItem) private var tag

    var body: some View {
        Button("Tag…", systemImage: "tag") { tag(entry) }
            .disabled(!catalog.isLive)
    }
}

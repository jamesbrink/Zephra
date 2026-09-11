import SwiftUI

/// "Share": the file, offered to the rest of the phone.
///
/// It asks rather than shares, because a menu item cannot both fetch a file and *be* a
/// `ShareLink` over the file it has not got yet — `LibraryRequests` does the fetch and raises
/// the sheet. The viewer's bar, which has a view to hang one on and a file already in hand,
/// uses a real `ShareLink`; the Mac draws the same line between `ShareLink` and `SharePicker`.
///
/// Greyed on `SaveToPhotosButton`'s rule: offline is fine for a file already here.
struct ShareButton: View {
    /// The picture or clip to offer.
    let entry: CachedEntry

    @Environment(LibraryCatalog.self) private var catalog
    /// Whether the file is already here, once the answer has come back from the store.
    @State private var isHeld = false

    var body: some View {
        ShareRequestButton(entry: entry)
            .disabled(!catalog.isLive && !isHeld)
            .task { isHeld = await catalog.hasFile(for: entry) }
    }
}

/// The button itself, split off so neither half holds a fourth stored property.
private struct ShareRequestButton: View {
    let entry: CachedEntry

    @Environment(\.shareLibraryItem) private var share

    var body: some View {
        Button("Share", systemImage: "square.and.arrow.up") { share(entry) }
    }
}

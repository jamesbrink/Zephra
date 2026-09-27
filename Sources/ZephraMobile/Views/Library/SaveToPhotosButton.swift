import SwiftUI

/// "Save to Photos": the picture, or the clip's MP4, into the phone's own library.
///
/// It works offline for anything already fetched, which is most of what somebody would want to
/// save — you save the one you have been looking at. It greys only when the file is not on
/// this phone *and* the Mac cannot be reached, which is the one case where there is nothing to
/// save at all; `LibraryCatalog.file(for:)` answers from the cache first and asks the Mac after.
struct SaveToPhotosButton: View {
    /// The picture or clip to keep.
    let entry: CachedEntry

    @Environment(LibraryCatalog.self) private var catalog
    /// Whether the file is already here, once the answer has come back from the store.
    @State private var availability = MediaAvailability()

    var body: some View {
        PhotoSaveButton(entry: entry)
        .disabled(!catalog.isLive(for: entry) && !availability.isHeld)
        .task(id: entry.id + entry.version + String(catalog.cacheRevision) + String(catalog.isLive(for: entry))) {
            let held = await catalog.hasFile(for: entry)
            if !Task.isCancelled { availability.isHeld = held }
        }
    }
}

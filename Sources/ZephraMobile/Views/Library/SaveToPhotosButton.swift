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
    @State private var isHeld = false

    var body: some View {
        Button("Save to Photos", systemImage: "square.and.arrow.down") {
            Task {
                guard let url = try? await catalog.file(for: entry) else { return }
                try? await PhotosSaver.save(url, isVideo: entry.isVideo)
            }
        }
        .disabled(!catalog.isLive && !isHeld)
        .task { isHeld = await catalog.hasFile(for: entry) }
    }
}

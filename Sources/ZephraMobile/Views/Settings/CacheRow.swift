import SwiftUI

/// What the phone is holding of the Mac's library, and how to be rid of it.
///
/// The number is the three stores together: the entries, the thumbnails and whatever whole
/// files have been fetched. Clearing asks first, because on a phone with no signal it is the
/// difference between having your library and not — and says as much, since what makes it safe
/// is that the Mac is the truth and this was only ever a copy.
struct CacheRow: View {
    @Environment(LibraryCatalog.self) private var catalog
    /// Whether the question is up.
    @State private var isAsking = false

    var body: some View {
        LabeledContent("Library cache", value: size)
            // The number is what the last count saw, and in the multi-host shape only this
            // screen's catalog re-reads the children's folders — so count again when the row
            // comes up, whatever the sync loops did before it.
            .task { await catalog.measureCache() }
        Button("Clear Cache", role: .destructive) { isAsking = true }
            .disabled(catalog.cacheBytes == 0)
            .confirmationDialog(
                "Clear the library cache?", isPresented: $isAsking, titleVisibility: .visible
            ) {
                Button("Clear Cache", role: .destructive) {
                    Task { await catalog.clearCache() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "The pictures stay on your Mac. This phone fetches them again the next "
                        + "time it needs them, which it cannot do while your Mac is out of reach.")
            }
    }

    /// The size, in the units a person reads. Zero is a word rather than "0 bytes", which
    /// reads like a failure.
    private var size: String {
        guard catalog.cacheBytes > 0 else { return "Empty" }
        return catalog.cacheBytes.formatted(.byteCount(style: .file))
    }
}

#Preview("Cache") {
    Form { CacheRow() }
        .environment(LibraryCatalog(libraryRoot: nil, filesRoot: nil))
}

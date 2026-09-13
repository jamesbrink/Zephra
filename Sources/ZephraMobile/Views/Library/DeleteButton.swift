import SwiftUI

/// "Delete Picture" or "Delete Clip", which asks before it does anything.
///
/// The Mac's wording: a menu that said "Delete" over a clip would be vaguer than the thing it
/// is about to do. The question itself is `LibraryRequests`', since a menu cannot raise one.
///
/// Greyed with the Mac out of reach. Deleting moves the file to the Mac's Recently Deleted,
/// which only the Mac can do; taking it off the phone alone would be a picture that came back
/// on the next sync.
struct DeleteButton: View {
    /// The picture to delete.
    let entry: CachedEntry

    @Environment(LibraryCatalog.self) private var catalog
    @Environment(\.confirmDeleteLibraryItem) private var confirm

    var body: some View {
        Button(title, systemImage: "trash", role: .destructive) { confirm(entry) }
            .disabled(!catalog.isLive(for: entry))
    }

    private var title: String { entry.isVideo ? "Delete Clip" : "Delete Picture" }
}

import SwiftUI

/// Both the viewer and the context menu ask the surface to own the save.
struct PhotoSaveButton: View {
    let entry: CachedEntry
    @Environment(\.saveLibraryItem) private var save
    @Environment(\.photoSaveIsBusy) private var isBusy

    var body: some View {
        Button("Save to Photos", systemImage: "square.and.arrow.down") { save(entry) }
            .disabled(isBusy)
    }
}

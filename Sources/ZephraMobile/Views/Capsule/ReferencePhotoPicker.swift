import PhotosUI
import SwiftUI

/// Owns the system picker's transient selection independently of reference resolution.
///
/// `maximum` is the room the well has left, so Apple's own sheet stops somebody choosing six
/// pictures for a place that holds three rather than taking three and saying so afterwards.
struct ReferencePhotoPicker: View {
    /// How many pictures may be chosen at once; never below one, since a picker that allows
    /// nothing is a door with nothing behind it.
    let maximum: Int
    let choose: ([PhotosPickerItem]) -> Void
    @State private var items: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(
            selection: $items, maxSelectionCount: max(1, maximum), matching: .images,
            photoLibrary: .shared()
        ) {
            Image(systemName: "photo.on.rectangle")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(maximum > 1 ? "Choose photos" : "Choose a photo")
        .onChange(of: items) { _, picked in
            guard !picked.isEmpty else { return }
            choose(picked)
            items = []
        }
    }
}

import PhotosUI
import SwiftUI

/// Owns the system picker's transient selection independently of reference resolution.
struct ReferencePhotoPicker: View {
    let choose: (PhotosPickerItem) -> Void
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
            Image(systemName: "photo.on.rectangle")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Choose a photo")
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            choose(picked)
            item = nil
        }
    }
}

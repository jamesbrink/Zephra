import SwiftUI
import ZephraEngine

/// The local-file alternative stays available even when the library has no matches.
struct ReferenceFileButton: View {
    @Environment(GenerationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Choose File…") {
            guard let png = ReferenceImagePicker.choose() else { return }
            ReferenceAdoption.use(png, into: store)
            dismiss()
        }
    }
}

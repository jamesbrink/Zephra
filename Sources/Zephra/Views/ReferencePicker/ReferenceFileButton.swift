import SwiftUI
import ZephraEngine

/// The local-file alternative stays available even when the library has no matches.
struct ReferenceFileButton: View {
    @Environment(GenerationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Choose File…") {
            let role = ReferenceRole(capabilities: store.descriptor.capabilities)
            Task {
                guard let url = await ReferenceImagePicker.choose(role: role) else { return }
                store.adoptReference { ReferenceImageEncoder.pngData(contentsOf: url) }
                dismiss()
            }
        }
    }
}

import SwiftUI
import ZephraCore
import ZephraEngine

/// The local-file alternative stays available even when the library has no matches.
///
/// It asks for as many pictures as the model still has room for, so the panel a one-picture
/// model raises is the single-selection panel it has always raised.
struct ReferenceFileButton: View {
    @Environment(GenerationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Choose File…") {
            let role = ReferenceRole(capabilities: store.descriptor.capabilities)
            let room = max(1, store.referenceRoom)
            Task {
                let urls = await ReferenceImagePicker.choose(role: role, upTo: room)
                guard !urls.isEmpty else { return }
                ReferenceAdoption.adopt(urls: urls, into: store)
                dismiss()
            }
        }
    }
}

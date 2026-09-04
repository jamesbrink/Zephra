import SwiftUI
import ZephraEngine

/// Puts a library image into the reference well beside the prompt.
///
/// "An edit hands back its source, not itself" and the off-main-actor read live in
/// `ReferenceAdoption`, the one door every source that offers a library picture as a reference
/// goes through — this button, the well's own menu and drop targets, and the picker sheet.
struct UseAsReferenceButton: View {
    /// The image to start from.
    let item: LibraryItem

    @Environment(GenerationStore.self) private var store

    var body: some View {
        Button { ReferenceAdoption.adopt(item, into: store) } label: {
            Text("Use as reference").frame(maxWidth: .infinity)
        }
        .disabled(!store.descriptor.capabilities.supportsReferenceImage)
    }
}

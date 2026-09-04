import SwiftUI
import ZephraEngine

/// Puts a library image into the reference well and returns to the canvas.
///
/// "An edit hands back its source, not itself" and the off-main-actor read live in
/// `ReferenceAdoption`, the one door every source that offers a library picture as a reference
/// goes through — this button, the well's own menu and drop targets, and the picker sheet.
struct UseAsReferenceButton: View {
    /// The image to start from.
    let item: LibraryItem

    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        Button {
            ReferenceAdoption.adopt(item, into: store)
            workspace.pane = .canvas
        } label: {
            Text("Use as reference").frame(maxWidth: .infinity)
        }
        .disabled(!store.descriptor.capabilities.supportsReferenceImage)
    }
}

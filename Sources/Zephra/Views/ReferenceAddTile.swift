import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// The `+` at the end of the reference strip: the same two doors the empty well has always
/// offered, in the place a person looks for "another one".
///
/// It draws `ReferencePlaceholder`, which is the empty well's own shape, so a strip with nothing
/// in it is the empty well — one tile, the same glyph, the same caption — and a strip with three
/// pictures ends in that same shape saying "Add". Nothing new to learn either way.
struct ReferenceAddTile: View {
    /// The caption under the glyph: the role's own word on an empty strip, and "Add" once there
    /// is something to add to.
    let title: String

    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        Button {
            workspace.showsReferencePicker = true
        } label: {
            ReferencePlaceholder(title: title, isTargeted: false)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("From Library…") { workspace.showsReferencePicker = true }
            Button("Choose File…") { chooseFile() }
        }
        .help(help)
        .accessibilityLabel(help)
    }

    private var help: String {
        role.emptyWellHelp(upTo: store.descriptor.capabilities.referenceImageCount.upperBound)
    }

    private var role: ReferenceRole {
        ReferenceRole(
            capabilities: store.descriptor.capabilities,
            continuing: store.settings.continuation != nil)
    }

    private func chooseFile() {
        let room = store.referenceRoom
        Task {
            let urls = await ReferenceImagePicker.choose(role: role, upTo: room)
            ReferenceAdoption.adopt(urls: urls, into: store)
        }
    }
}

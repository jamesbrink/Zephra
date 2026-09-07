import SwiftUI
import ZephraCore
import ZephraEngine

/// Sets the next generation up to animate this picture, and returns to the canvas.
///
/// The title says which picture is being animated: "Animate" for a picture, "Animate from Last
/// Frame" for a clip, since a clip's poster is only its first frame and Animate means the one
/// the clip ends on. `ReferenceAdoption.animate(_:into:)` — never `adopt(_:into:)` — reads the
/// bytes: an edit hands back its own source under `adopt`, and that rule is for starting a new
/// picture from an old one's origin, not for what Animate means by "this picture".
struct AnimateButton: View {
    /// The image to animate.
    let item: LibraryItem

    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        Button {
            ReferenceAdoption.animate(item, into: store)
            workspace.pane = .canvas
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .disabled(!store.canAnimate)
        .help(helpText)
    }

    private var title: String { item.isVideo ? "Animate from Last Frame" : "Animate" }

    private var helpText: String {
        guard let animator = ModelCatalog.animator() else { return "" }
        let subject = item.isVideo ? "this clip's last frame" : "this picture"
        return "Make a clip from \(subject)" + ModelLoadNote.text(for: animator, store: store)
    }
}

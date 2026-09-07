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

    private var title: String { CommandTarget.animateTitle(forClip: item.isVideo) }

    /// `ActionAvailability`'s reason while the button is disabled — a `LibraryItem` is always
    /// already on disk, so `hasSource` is always true here — and what pressing it would do
    /// first while it is live.
    private var helpText: String {
        let reason = ActionAvailability.animateDisabledReason(hasSource: true, store: store)
        guard reason.isEmpty, let animator = ModelCatalog.animator() else { return reason }
        let subject = item.isVideo ? "this clip's last frame" : "this picture"
        return "Make a clip from \(subject)" + ModelLoadNote.text(for: animator, store: store)
    }
}

import SwiftUI
import ZephraCore
import ZephraEngine

/// Sets the next generation up to carry this clip on from where it ends, and returns to the
/// canvas.
///
/// `ReferenceAdoption.extend(_:into:)` reads the clip's last frames off the main actor and puts
/// the last of them in the well with the rest behind it; Generate then makes the next segment
/// and joins it onto this clip. Shown for clips only: a picture has no end to carry on from.
struct ExtendClipButton: View {
    /// The clip to carry on.
    let item: LibraryItem

    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        Button {
            ReferenceAdoption.extend(item, into: store)
            workspace.pane = .canvas
        } label: {
            Text(CommandTarget.extendTitle).frame(maxWidth: .infinity)
        }
        .disabled(!reason.isEmpty)
        .help(helpText)
    }

    private var reason: String {
        ActionAvailability.extendDisabledReason(record: item.provenance.record, store: store)
    }

    /// `ActionAvailability`'s reason while the button is disabled, and what pressing it would
    /// do first while it is live.
    private var helpText: String {
        guard reason.isEmpty, let modelID = item.modelID,
            let continuer = ModelCatalog.continuer(for: modelID)
        else { return reason }
        return "Make the next part of this clip" + ModelLoadNote.text(for: continuer, store: store)
    }
}

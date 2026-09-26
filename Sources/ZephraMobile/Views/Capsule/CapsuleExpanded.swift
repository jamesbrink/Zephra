import SwiftUI
import ZephraLinkProtocol

/// The capsule with everything out: the editor, the well, the settings, and the button.
///
/// The order is the Mac's — what the picture is, what it starts from, what it costs — read top
/// to bottom instead of left to right, because that is the shape of a phone. Nothing here is
/// hidden by a state of the engine: a run carries its own settings, so a size moved while the
/// Mac works is the next run's, exactly as on the Mac.
struct CapsuleExpanded: View {
    /// What the model in force will accept, which decides every control that is drawn.
    let capabilities: CapabilitiesSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PromptHistoryControls()
            PromptEditor()
            if capabilities.supportsReferenceImage {
                ReferenceWell(capabilities: capabilities)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if capabilities.supportsNegativePrompt {
                NegativePromptField()
            }
            Divider()
            ControlsGrid(capabilities: capabilities)
            CapsuleActions()
        }
        .padding(.horizontal, 14)
    }
}

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
    /// Where the phone is looking, which owns whether the settings are showing; the chevron
    /// puts them away, and the keyboard with them.
    @Environment(MobileSelection.self) private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PromptEditor()
                if capabilities.supportsReferenceImage {
                    ReferenceWell(capabilities: capabilities)
                }
            }
            if capabilities.supportsNegativePrompt {
                NegativePromptField()
            }
            Divider()
            ControlsGrid(capabilities: capabilities)
            HStack(alignment: .center, spacing: 12) {
                CountControl()
                Spacer(minLength: 8)
                Button {
                    selection.collapseCapsule()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Put the settings away")
                GenerateButton()
            }
        }
        .padding(.horizontal, 14)
    }
}

import SwiftUI
import ZephraLinkClient
import ZephraStyle

/// The one control surface the phone has: the prompt, what the next press of Generate will
/// ask for, and the step segments riding its top edge.
///
/// The Mac's capsule, in the room a phone has. It sits in the canvas's bottom safe area rather
/// than in a sheet, so the tab bar stays a tap away while a prompt is being typed, and it is
/// made of system material for the reason the Mac's is: the picture behind it tints every
/// control on it.
///
/// Collapsed it is a prompt preview followed by the actions. Expanded it is the whole of the Mac's
/// capsule — the editor, the reference well, the settings and the negative prompt — because a
/// phone cannot show them all at once and a person setting up a run is not also watching one.
struct PromptCapsule: View {
    @Environment(GenerationDispatch.self) private var dispatch
    @Environment(PromptDraft.self) private var draft
    /// Where the phone is looking, which owns whether the settings are showing.
    @Environment(MobileSelection.self) private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StepSegments(progress: StepProgress(dispatch.hosts.client.snapshot?.engine))
                .padding(.horizontal, ZephraChrome.capsuleRadius)
            DestinationPicker()
            if let model = dispatch.models.first(where: { $0.id == draft.modelID }) {
                let capabilities = model.capabilities
                if selection.capsuleIsExpanded {
                    CapsuleExpanded(capabilities: capabilities)
                } else {
                    CapsuleCollapsed()
                }
            } else {
                Text("Waiting for your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            }
            if dispatch.target == nil || dispatch.target?.id == dispatch.hosts.visible?.id {
                ConnectionNote(state: dispatch.hosts.client.connection)
            }
        }
        .padding(.vertical, 12)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: ZephraChrome.capsuleRadius, style: .continuous)
        )
        .padding(.horizontal, MobileChrome.sideMargin)
        .padding(.bottom, 6)
    }
}

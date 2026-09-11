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
/// Collapsed it is one line of prompt and the button. Expanded it is the whole of the Mac's
/// capsule — the editor, the reference well, the settings and the negative prompt — because a
/// phone cannot show them all at once and a person setting up a run is not also watching one.
struct PromptCapsule: View {
    @Environment(LinkClient.self) private var client
    @Environment(PromptDraft.self) private var draft
    /// Whether the settings are showing.
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StepSegments(progress: StepProgress(client.snapshot?.engine))
                .padding(.horizontal, ZephraChrome.capsuleRadius)
            if let snapshot = client.snapshot {
                let capabilities = snapshot.model(named: draft.modelID).capabilities
                if isExpanded {
                    CapsuleExpanded(capabilities: capabilities, isExpanded: $isExpanded)
                } else {
                    CapsuleCollapsed(isExpanded: $isExpanded)
                }
            } else {
                Text("Waiting for your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            }
            if !client.connection.isLive {
                Label("Offline. This is the last thing your Mac said.", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
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

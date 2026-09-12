import SwiftUI
import ZephraStyle

/// How many seeds the next press is worth, on the capsule at rest.
///
/// The collapsed capsule is one line of prompt and a button, and a press of that button is
/// worth whatever `CountControl` was last set to — which is behind the chevron, where nobody
/// can see it. So the one number that changes what a press costs is shown here when it is not
/// one, and tapping it opens the settings where it is changed. Nothing is drawn at a count of
/// one, which is every session that never touched the stepper.
struct CountChip: View {
    @Environment(PromptDraft.self) private var draft
    @Environment(MobileSelection.self) private var selection

    var body: some View {
        if draft.count > 1 {
            Button {
                selection.capsuleIsExpanded = true
            } label: {
                Chip("\u{00D7}\(draft.count)")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Seeds per press")
            .accessibilityValue("\(draft.count)")
            .accessibilityHint("Opens the settings")
        }
    }
}

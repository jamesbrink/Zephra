import SwiftUI

/// Keep the actions inside the capsule when Stop or extra model settings need more room.
struct PromptControls: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 12) {
                ControlsRow()
                Spacer(minLength: 12)
                actions
            }
            VStack(alignment: .leading, spacing: 12) {
                ControlsRow(wraps: true)
                actions.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var actions: some View {
        HStack(alignment: .bottom, spacing: 12) {
            BatchCountControl()
            StopButton()
            GenerateButton()
        }
        .fixedSize()
    }
}

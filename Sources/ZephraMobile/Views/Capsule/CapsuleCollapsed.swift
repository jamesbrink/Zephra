import SwiftUI
import ZephraStyle

/// The prompt gets the full width; actions below it can grow without squeezing its text.
struct CapsuleCollapsed: View {
    @Environment(PromptDraft.self) private var draft
    /// Where the phone is looking, which owns both the settings being up and the keyboard.
    @Environment(MobileSelection.self) private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                selection.expandCapsule(focusingPrompt: true)
            } label: {
                Text(draft.settings.prompt.isEmpty ? "Describe a picture…" : draft.settings.prompt)
                    .font(.callout)
                    .lineLimit(2)
                    .foregroundStyle(draft.settings.prompt.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(
                            cornerRadius: ZephraChrome.fieldRadius, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Prompt")
            .accessibilityHint("Opens the prompt and the keyboard")
            CountChip()
            GenerateButton()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
    }
}

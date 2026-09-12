import SwiftUI
import ZephraStyle

/// The capsule at rest: the prompt's first line, a way to open the settings, and the button.
///
/// One line, because what a person wants from a phone in their pocket is to see the picture
/// and press Generate again. The line is drawn as a field rather than as plain text, since one
/// tap on it opens the editor with the keyboard already up: it behaves like a field, so it
/// should look like one.
struct CapsuleCollapsed: View {
    @Environment(PromptDraft.self) private var draft
    /// Where the phone is looking, which owns both the settings being up and the keyboard.
    @Environment(MobileSelection.self) private var selection

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                selection.expandCapsule(focusingPrompt: true)
            } label: {
                Text(draft.settings.prompt.isEmpty ? "Describe a picture…" : draft.settings.prompt)
                    .font(.callout)
                    .lineLimit(1)
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
        }
        .padding(.horizontal, 14)
    }
}

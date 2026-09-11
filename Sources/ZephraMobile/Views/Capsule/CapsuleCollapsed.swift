import SwiftUI

/// The capsule at rest: the prompt's first line, a way to open the settings, and the button.
///
/// One line, because what a person wants from a phone in their pocket is to see the picture
/// and press Generate again. Tapping the line opens the editor, which is where the prompt is
/// actually changed.
struct CapsuleCollapsed: View {
    @Environment(PromptDraft.self) private var draft
    /// Whether the settings are showing.
    @Binding var isExpanded: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                isExpanded = true
            } label: {
                Text(draft.settings.prompt.isEmpty ? "Describe a picture…" : draft.settings.prompt)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(draft.settings.prompt.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Prompt")
            .accessibilityHint("Opens the prompt and its settings")
            GenerateButton()
        }
        .padding(.horizontal, 14)
    }
}

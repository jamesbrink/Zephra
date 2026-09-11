import SwiftUI

/// What to steer the picture away from. Drawn only for a model that reads one, which is what
/// `CapsuleExpanded` asks before it places this.
struct NegativePromptField: View {
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        TextField("Avoid…", text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1...2)
            .accessibilityLabel("Negative prompt")
    }

    /// An empty field means no negative prompt at all, not an empty one, so the settings carry
    /// nil rather than "" and the Mac records what was actually asked for.
    private var text: Binding<String> {
        Binding(
            get: { draft.settings.negativePrompt ?? "" },
            set: { draft.settings.negativePrompt = $0.isEmpty ? nil : $0 })
    }
}

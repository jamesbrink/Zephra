import SwiftUI
import ZephraEngine

/// What to steer the image away from. Shown only for models that read a negative prompt, so
/// Z-Image, which ignores one, does not offer a field that would do nothing.
struct NegativePromptField: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        if store.descriptor.capabilities.supportsNegativePrompt {
            TextField("Avoid…", text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1...2)
                .accessibilityLabel("Negative prompt")
        }
    }

    /// An empty field means no negative prompt at all, not an empty one, so the settings carry
    /// nil rather than "" and a saved image records what was actually asked for.
    private var text: Binding<String> {
        Binding(
            get: { store.settings.negativePrompt ?? "" },
            set: { store.settings.negativePrompt = $0.isEmpty ? nil : $0 }
        )
    }
}

#Preview("Negative prompt") {
    NegativePromptField()
        .padding()
        .frame(width: 420)
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.guided))
}

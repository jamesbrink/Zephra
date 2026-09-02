import SwiftUI
import ZephraEngine

/// The prompt field. One line at rest, growing to four as the description does, and never
/// taller than that, so the capsule stays a capsule. It stays editable while the model works, so
/// the next prompt can be queued.
struct PromptEditor: View {
    @Environment(GenerationStore.self) private var store
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var store = store
        TextField("Describe an image…", text: $store.settings.prompt, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(1...4)
            .focused($isFocused)
            .onSubmit { store.generateFromInterface() }
            .onAppear { isFocused = store.settings.prompt.isEmpty }
            .accessibilityLabel("Prompt")
    }
}

#Preview("Prompt") {
    PromptEditor()
        .padding()
        .frame(width: 420)
        .environment(GenerationStore.preview(state: .ready))
}

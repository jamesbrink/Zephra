import SwiftUI
import ZephraEngine

/// The prompt field. It claims the whole of the space the prompt area already occupied — one
/// line of text, the gap under it, and the height of the well beside it — so the capsule keeps
/// the shape it had and all of that area carries a caret. Before, the field hugged its single
/// line and the rest of the band was space that only looked like somewhere to type.
///
/// Growing to six lines and no further, so a pasted essay scrolls rather than turning the
/// capsule into a page. A minimum height rather than filling what it is given: told to fill, a
/// field inside a floating panel grows the panel to the height of the window.
///
/// Focus belongs to the row rather than to this view, because the whole row is the target: a
/// click in the corner under the well has to land in the prompt.
struct PromptEditor: View {
    @Environment(GenerationStore.self) private var store
    private let focus: FocusState<Bool>.Binding

    init(focus: FocusState<Bool>.Binding) {
        self.focus = focus
    }

    var body: some View {
        @Bindable var store = store
        TextField("Describe an image…", text: $store.settings.prompt, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(1...6)
            .focused(focus)
            .onSubmit { store.generateFromInterface() }
            .onAppear { focus.wrappedValue = store.settings.prompt.isEmpty }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .accessibilityLabel("Prompt")
    }
}

#Preview("Prompt") {
    @Previewable @FocusState var focused: Bool
    PromptEditor(focus: $focused)
        .padding()
        .frame(width: 420)
        .environment(GenerationStore.preview(state: .ready))
}

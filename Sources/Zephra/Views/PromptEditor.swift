import SwiftUI
import ZephraEngine

/// The prompt. A real multi-line editor: Return puts in a line break and Command-Return starts
/// the generation, which is why this is a text view and not a `TextField`. A field on a
/// vertical axis looks the same and is not the same — Return there commits the line rather than
/// breaking it, and there is no way to ask it for the other behaviour. The view is
/// `PromptTextView`, ours, rather than `TextEditor`, so a selection stops at the text.
///
/// It claims the whole of the space the prompt area already occupied — one line of text, the
/// gap under it, and the height of the well beside it — so the capsule keeps the shape it had
/// and all of that area carries a caret. It then grows with the text to about six lines and
/// scrolls beyond that, so a pasted essay does not turn the capsule into a page.
///
/// The height comes from a hidden twin of the text rather than from the editor, because the
/// editor is a scroll view: it has no opinion about how tall it should be and will take
/// whatever it is offered.
///
/// Focus belongs to the row, because the whole row is the click target.
struct PromptEditor: View {
    @Environment(GenerationStore.self) private var store
    @Binding var focus: Bool
    @State private var textHeight: CGFloat = 0

    /// The band the prompt area has always been, and the ceiling it scrolls past.
    private static let restingHeight: CGFloat = 76
    private static let ceiling: CGFloat = 148

    var body: some View {
        @Bindable var store = store
        PromptTextView(text: $store.settings.prompt, isFocused: $focus, history: store.promptHistory.entries.map(\.prompt))
            .onAppear { focus = store.settings.prompt.isEmpty }
            .frame(height: min(max(textHeight, Self.restingHeight), Self.ceiling))
            .background(alignment: .topLeading) { twin }
            .overlay(alignment: .topLeading) { placeholder }
            .accessibilityLabel("Prompt")
    }

    /// The text laid out at the editor's own width, measured and never drawn.
    private var twin: some View {
        Text(store.settings.prompt.isEmpty ? " " : store.settings.prompt)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
    }

    @ViewBuilder
    private var placeholder: some View {
        if store.settings.prompt.isEmpty {
            Text("Describe an image…")
                .font(.body)
                .foregroundStyle(.tertiary)
                .allowsHitTesting(false)
        }
    }
}

#Preview("Prompt") {
    @Previewable @State var focused = false
    PromptEditor(focus: $focused)
        .padding()
        .frame(width: 420)
        .environment(GenerationStore.preview(state: .ready))
}

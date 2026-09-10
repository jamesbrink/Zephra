import SwiftUI
import ZephraCore
import ZephraEngine

/// Typing a size in, from the Size menu: width and height in one field, a button to turn the
/// frame the other way, and under them the grid the model runs on. Return keeps it and
/// closes; Escape closes without.
///
/// What counts as a size is `SizeEntry`'s business, so the rule is tested rather than read off
/// the field. Nothing is written to the store until Return, and a typed size off the model's
/// grid lands on the nearest point of it, as the hint says it will.
struct SizeEntryPopover: View {
    @Binding var isPresented: Bool
    @State private var text: String
    @Environment(GenerationStore.self) private var store

    init(isPresented: Binding<Bool>, initialText: String) {
        _isPresented = isPresented
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("Size", text: $text, prompt: Text("Width × Height"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospacedDigit())
                    .frame(width: 160)
                    .accessibilityLabel("Custom size")
                    .onSubmit(commit)
                Button(action: swap) {
                    Image(systemName: "rectangle.portrait.rotate")
                }
                .buttonStyle(.accessoryBar)
                .disabled(SizeEntry.typed(text) == nil)
                .help("Turn the frame the other way")
                .accessibilityLabel("Swap width and height")
            }
            SizeEntryHint(text: text, capabilities: store.descriptor.capabilities)
        }
        .padding(12)
        .onExitCommand { isPresented = false }
    }

    private func commit() {
        guard let size = SizeEntry.parse(text, for: store.descriptor.capabilities) else { return }
        store.settings.size = size
        isPresented = false
    }

    private func swap() {
        guard let typed = SizeEntry.typed(text) else { return }
        text = SizeEntry.text(ImageSize(width: typed.height, height: typed.width))
    }
}

#Preview("Size entry") {
    SizeEntryPopover(isPresented: .constant(true), initialText: "768 × 512")
        .environment(GenerationStore.preview(state: .ready))
}

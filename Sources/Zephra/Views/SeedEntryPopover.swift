import SwiftUI
import ZephraEngine

/// Typing a seed in, over the seed label: the whole number, the whole value in hex, or the
/// short label off another picture's inspector. Return keeps it and closes; Escape closes
/// without.
///
/// What counts as a seed is `SeedEntry`'s business, so the rule is tested rather than read off
/// the field. Nothing is written to the store until Return, and a value the parser refuses
/// leaves the field up with the reason under it rather than keeping some guess. The field
/// opens on `initialText`, the current seed spelled the way Settings spells seeds — the
/// whole value, not the label, so Return with nothing typed keeps the seed it had.
struct SeedEntryPopover: View {
    @Binding var isPresented: Bool
    @State private var text: String
    @Environment(GenerationStore.self) private var store

    init(isPresented: Binding<Bool>, initialText: String) {
        _isPresented = isPresented
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Seed", text: $text, prompt: Text("Number or 7A3F·9C2E"))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .frame(width: 220)
                .onSubmit(commit)
            SeedEntryHint(text: text)
        }
        .padding(12)
        .onExitCommand { isPresented = false }
    }

    private func commit() {
        guard let parsed = SeedEntry.parse(text) else { return }
        store.settings.seed = parsed
        isPresented = false
    }
}

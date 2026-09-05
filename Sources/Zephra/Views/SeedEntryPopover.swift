import SwiftUI
import ZephraEngine

/// Typing a seed in, over the seed label: the whole number, or the short label off another
/// picture's inspector. Return keeps it and closes; Escape closes without.
///
/// What counts as a seed is `SeedEntry`'s business, so the rule is tested rather than read off
/// the field. Nothing is written to the store until Return, and a value the parser refuses
/// leaves the field up with the reason under it rather than keeping some guess.
struct SeedEntryPopover: View {
    @Binding var isPresented: Bool
    @State private var text = ""
    @Environment(GenerationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Seed", text: $text, prompt: Text("Number or 7A3F·9C2E"))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .frame(width: 220)
                .onSubmit(commit)
            Text(hint)
                .font(.caption)
                .foregroundStyle(isValid ? .secondary : Color.red)
        }
        .padding(12)
        .onAppear { text = String(store.settings.seed) }
        .onExitCommand { isPresented = false }
    }

    private var parsed: UInt64? { SeedEntry.parse(text) }

    private var isValid: Bool { text.isEmpty || parsed != nil }

    private var hint: String {
        if let parsed { return "Press Return to use \(parsed.shortSeedLabel)." }
        return text.isEmpty ? "The seed as a number, or its short label." : "Not a seed."
    }

    private func commit() {
        guard let parsed else { return }
        store.settings.seed = parsed
        isPresented = false
    }
}

import SwiftUI
import ZephraCore

/// The field a seed is typed into, and the one button that takes it.
///
/// Split from the sheet the way `SizeEntryField` is, so the text lives beside the field that
/// edits it without the sheet holding four things: the sheet is the frame, the spelling and the
/// rule, this is the entry. It opens on the seed in force, spelled exactly, so Return with
/// nothing typed keeps the seed it had.
struct SeedEntryField: View {
    /// The seed in force, spelled the way Settings spells seeds.
    let initialText: String
    /// What to do with a seed that parsed.
    let take: (UInt64) -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Seed", text: $text)
                .font(.body.monospaced())
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .onSubmit(use)
                .accessibilityLabel("Seed")
            Button("Use This Seed", action: use)
                .buttonStyle(.borderedProminent)
                .disabled(SeedEntry.parse(text) == nil)
        }
        .task { text = initialText }
    }

    private func use() {
        guard let seed = SeedEntry.parse(text) else { return }
        take(seed)
    }
}

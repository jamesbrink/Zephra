import SwiftUI

/// The noise seed, as `SeedLabel` spells it, with a shuffle for a fresh one; a tap on the
/// label opens the sheet a seed is typed into.
///
/// The label is the leading eight hex digits, which is `SeedFormat.hex` on the Mac and its
/// default there. The whole number is in the accessibility label and in the sheet, because the
/// whole number is what reproduces a picture.
struct SeedControl: View {
    @Environment(PromptDraft.self) private var draft
    /// Whether the sheet for typing a seed is up.
    @State private var isEntering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isEntering = true
            } label: {
                Text(SeedLabel.text(draft.settings.seed))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Seed \(String(draft.settings.seed))")
            .accessibilityHint("Opens a field to type a seed")
            Button {
                draft.randomizeSeed()
            } label: {
                Image(systemName: "shuffle")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Pick a new seed")
        }
        .sheet(isPresented: $isEntering) { SeedEntrySheet() }
    }
}

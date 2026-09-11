import SwiftUI
import ZephraCore

/// The noise seed, as `SeedFormat` spells it, with a shuffle for a fresh one; a tap on the
/// label opens the sheet a seed is typed into.
///
/// `SeedFormat.hex` always: the Mac's own type and its default there, and the only spelling the
/// phone offers, since there is no Settings > General here to choose the decimal in. The whole
/// number is in the accessibility label and in the sheet, because the whole number is what
/// reproduces a picture.
struct SeedControl: View {
    @Environment(PromptDraft.self) private var draft
    /// Whether the sheet for typing a seed is up.
    @State private var isEntering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isEntering = true
            } label: {
                Text(SeedFormat.hex.label(draft.settings.seed))
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

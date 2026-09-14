import SwiftUI
import ZephraCore

/// The noise seed, as `SeedFormat` spells it, with a shuffle for a fresh one and a lock that
/// keeps this one across runs; a tap on the label opens the sheet a seed is typed into.
///
/// The spelling is `\.seedFormat` from the Settings tab, exactly as on the Mac: the short hex
/// label by default, the whole number for the person who copies seeds between tools. The whole
/// number is in the accessibility label and in the sheet whichever is chosen, because the whole
/// number is what reproduces a picture.
struct SeedControl: View {
    @Environment(PromptDraft.self) private var draft
    @Environment(\.seedFormat) private var format
    /// Whether the sheet for typing a seed is up.
    @State private var isEntering = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { controls }.fixedSize()
            VStack(alignment: .leading, spacing: 8) { controls }
        }
        .sheet(isPresented: $isEntering) { SeedEntrySheet() }
    }

    @ViewBuilder private var controls: some View {
        Button {
            isEntering = true
        } label: {
            Text(format.label(draft.settings.seed))
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
        SeedLockToggle()
    }
}

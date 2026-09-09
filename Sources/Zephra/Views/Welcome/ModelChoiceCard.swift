import SwiftUI
import ZephraCore
import ZephraEngine

/// One model in the chooser: a picture it made, its name, what it is for, and what choosing it
/// would cost here.
///
/// A real `Button`, so Tab reaches it and Space presses it, and the focus ring is wanted —
/// unlike the library grid, where a ring around a whole pane says nothing, here it says which
/// card the keyboard is on.
///
/// A model that would page on this Mac is not dimmed and not disabled. Memory is a note, not a
/// gate — the same rule `ModelMenu` follows — and `ModelChoiceFacts` is where the note goes.
struct ModelChoiceCard: View {
    /// The model, its fit, and whether it is this Mac's recommendation.
    let choice: ModelChoice
    /// Whether this is the selected card.
    let isChosen: Bool
    /// Selects this card.
    let onChoose: () -> Void

    var body: some View {
        Button(action: onChoose) {
            VStack(alignment: .leading, spacing: 0) {
                ModelSampleImage(choice: choice)
                details
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .chromePanel(.inset)
            .overlay {
                RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous)
                    .strokeBorder(isChosen ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        // No label of its own: a button's label replaces its children rather than adding to
        // them, and what is worth hearing is the whole card — the badge, the name, the line
        // about the model, what it downloads and how it runs here.
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                ModelDot(choice.model.id)
                Text(choice.model.fullName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(choice.portrait?.summary ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
            ModelChoiceFacts(choice: choice)
        }
        .multilineTextAlignment(.leading)
        .padding(12)
    }
}

#Preview("Cards") {
    VStack(spacing: 16) {
        ForEach(ModelChoice.all(for: MemoryBudget(physicalMemory: 16 << 30)).prefix(2)) { choice in
            ModelChoiceCard(choice: choice, isChosen: choice.isRecommended) {}
        }
    }
    .frame(width: 320)
    .padding(24)
    .background(Color.canvasBackground)
    .environment(GenerationStore.preview(state: .idle))
}

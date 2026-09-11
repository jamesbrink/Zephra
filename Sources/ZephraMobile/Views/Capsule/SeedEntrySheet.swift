import SwiftUI
import ZephraCore

/// A seed typed or pasted in.
///
/// `SeedEntry` is the parser, the Mac's and ours: the whole decimal number a file name
/// carries, sixteen hex digits behind `0x`, or the eight the label shows, which comes back as
/// that half over zeros — the same seed the label would draw. Anything else is refused rather
/// than guessed at, and the button stays off while it is.
struct SeedEntrySheet: View {
    @Environment(PromptDraft.self) private var draft
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Seed", text: $text)
                        .font(.body.monospaced())
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .onSubmit(use)
                        .accessibilityLabel("Seed")
                    Button("Use This Seed", action: use)
                        .disabled(SeedEntry.parse(text) == nil)
                } footer: {
                    Text("The whole number, or the eight characters the capsule shows.")
                }
            }
            .navigationTitle("Seed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .task { text = SeedFormat.hex.exactText(draft.settings.seed) }
        }
        .presentationDetents([.medium])
    }

    private func use() {
        guard let seed = SeedEntry.parse(text) else { return }
        draft.settings.seed = seed
        dismiss()
    }
}

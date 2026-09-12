import SwiftUI
import ZephraCore

/// A seed typed or pasted in.
///
/// `SeedEntry` is the parser, the Mac's and ours: the whole decimal number a file name
/// carries, sixteen hex digits behind `0x`, or the eight the label shows, which comes back as
/// that half over zeros — the same seed the label would draw. Anything else is refused rather
/// than guessed at, and the button stays off while it is.
///
/// Both spellings are read whichever one Settings shows; what changes with the setting is what
/// the field opens on and what the footer says the field takes first.
struct SeedEntrySheet: View {
    @Environment(PromptDraft.self) private var draft
    @Environment(\.seedFormat) private var format
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SeedEntryField(initialText: format.exactText(draft.settings.seed)) { seed in
                        draft.settings.seed = seed
                        dismiss()
                    }
                } footer: {
                    Text(Self.footer(for: format))
                }
            }
            .navigationTitle("Seed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// What the field takes, led by the spelling the capsule is showing, since that is the one
    /// somebody is most likely reading a seed off.
    static func footer(for format: SeedFormat) -> String {
        switch format {
        case .hex: "The whole number, or the eight characters the capsule shows."
        case .decimal: "The whole number the capsule shows, or sixteen hex digits behind 0x."
        }
    }
}

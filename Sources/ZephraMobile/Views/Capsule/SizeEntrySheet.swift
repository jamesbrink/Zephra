import SwiftUI
import ZephraCore
import ZephraLinkProtocol

/// A size typed in: two whole numbers with whatever sits between them, fitted to the model's
/// own grid.
///
/// `SizeEntry` is the parser, the Mac's and ours, so `800 x 500` on a grid of 32 becomes
/// 800 × 512 here exactly as it does there — and the hint under the field says the rule before
/// anything is typed rather than refusing afterwards.
struct SizeEntrySheet: View {
    /// What the model in force will accept.
    let capabilities: CapabilitiesSummary
    @Environment(PromptDraft.self) private var draft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SizeEntryField(capabilities: capabilities) { size in
                        draft.settings.size = size
                        dismiss()
                    }
                } footer: {
                    Text(SizeEntry.rule(for: capabilities.capabilities))
                }
            }
            .navigationTitle("Custom Size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

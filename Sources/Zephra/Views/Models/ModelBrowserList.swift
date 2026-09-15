import SwiftUI
import ZephraCore
import ZephraEngine

/// The browser's cards and the footer under them, with the selection between the two.
///
/// Split from `ModelBrowserSheet` because the sheet would otherwise hold the budget, the
/// selection and the way out at once, and a view is allowed three stored properties. The sheet
/// is the frame and the header; this is what is inside it.
struct ModelBrowserList: View {
    @Environment(GenerationStore.self) private var store
    @Environment(\.memoryBudget) private var budget

    /// Which card is selected, seeded from the model the window is already pointing at so the
    /// footer opens describing that rather than an arbitrary first card.
    @State private var chosen: ModelDescriptor.ID?

    var body: some View {
        let choices = ModelChoice.all(for: budget)
        ScrollView {
            ModelChoiceGrid(choices: choices, chosen: $chosen)
                .padding(.top, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        Divider()
        ModelBrowserFooter(choice: selection(among: choices))
            .onAppear { if chosen == nil { chosen = store.descriptor.id } }
    }

    /// The selected model, falling back to the chosen one and then to the first card, so the
    /// footer always has something to describe.
    private func selection(among choices: [ModelChoice]) -> ModelChoice {
        choices.first { $0.id == chosen }
            ?? choices.first { $0.id == store.descriptor.id }
            ?? choices[0]
    }
}

import SwiftUI
import ZephraCore
import ZephraEngine

/// Every model the catalog knows, the ones this Mac runs at their default size first.
///
/// Nothing is hidden: a model that would page here is still listed and still choosable, with
/// its own note saying what it would take — the rule `ModelMenu` already follows, since a
/// model that pages at its default size still runs at a smaller one.
///
/// The columns are adaptive because the window's floor is 880 by 560: the grid reflows to two
/// columns there, and `WelcomeView`'s scroll view carries it. That view also caps the width
/// this is laid out in, which is what stops a wide display putting all six in one row.
struct ModelChoiceGrid: View {
    /// Every model, judged against this Mac's budget.
    let choices: [ModelChoice]

    /// Which card is selected.
    @Binding var chosen: ModelDescriptor.ID?

    var body: some View {
        // No `ScrollView` of its own: `WelcomeView` scrolls the header and the grid together,
        // and a scroll view nested in that one would take the whole height greedily and leave
        // nothing for the spacers that centre the screen on a tall window.
        LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
            ForEach(choices) { choice in
                ModelChoiceCard(choice: choice, isChosen: choice.id == chosen) {
                    chosen = choice.id
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 16, alignment: .top)]
    }
}

#Preview("Grid") {
    @Previewable @State var chosen: String? = ModelCatalog.default.id
    ModelChoiceGrid(choices: ModelChoice.all(for: MemoryBudget(physicalMemory: 16 << 30)), chosen: $chosen)
        .frame(width: 1100, height: 560)
        .background(Color.canvasBackground)
        .environment(GenerationStore.preview(state: .idle))
}

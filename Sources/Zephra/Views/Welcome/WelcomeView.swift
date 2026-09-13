import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// The first-launch model chooser, filling the window in place of the workspace.
///
/// A first launch used to decide for the user: the catalog's default was loaded and its
/// download started before the window had settled. What each model costs and how it would run
/// here were already computed — `ModelAvailability`, `MemoryFit` — and shown nowhere until a
/// toolbar menu was found, by which point gigabytes were already moving.
///
/// So the choice is made first, on one screen: what each model makes, what it really
/// transfers, and how it runs on this Mac. Nothing is fetched while it is up.
///
/// The cards sit in a column of their own rather than stretching to the window's width: a
/// 34-inch display would otherwise lay six of them out in one thin strip under the headline
/// with the rest of the screen empty. Inside that column the header and the grid are centred
/// on what space there is, and scroll together once there is not enough.
struct WelcomeView: View {
    @Environment(\.memoryBudget) private var budget

    /// Which card is selected. Seeded from the catalog's own answer for this Mac, so the
    /// screen opens on a recommendation rather than on nothing.
    @State private var chosen: ModelDescriptor.ID?

    /// Three cards to a row at the widest, which is what keeps a card a card. The figure is
    /// also what makes both rows fit at the 1200 x 840 the window opens at: wider cards are
    /// taller cards, and a second row cut off by the footer is the first thing a person sees.
    private static let contentWidth: CGFloat = 1040

    var body: some View {
        let choices = ModelChoice.all(for: budget)
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    // The spacers rather than an alignment: a `minHeight` with `.center` is
                    // satisfied by the content's own height and leaves it at the top, and a
                    // headline pinned to the top of a mostly empty window reads as a screen
                    // that has not finished loading.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        WelcomeHeader()
                        ModelChoiceGrid(choices: choices, chosen: $chosen)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: Self.contentWidth)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            Divider()
            WelcomeFooter(choice: selection(among: choices))
        }
        .background(Color.canvasBackground)
        .onAppear { if chosen == nil { chosen = Self.opening(among: choices)?.id } }
    }

    /// Which card the screen opens on: this Mac's recommendation, else the first model it can
    /// actually hold, else nothing — a Mac too small for the whole catalog opens on no
    /// selection rather than on a card whose button is out for a reason nobody chose.
    private static func opening(among choices: [ModelChoice]) -> ModelChoice? {
        // `isRecommended` already implies selectable (`ModelChoice.all`); the second line is
        // for the Mac that has no recommendation at all.
        choices.first(where: \.isRecommended) ?? choices.first(where: \.isSelectable)
    }

    /// The selected model, falling back to what the screen would have opened on so the footer
    /// always has something to describe — and, on a Mac that can hold none of them, to the
    /// first card, whose footer then says what it would take and offers no press.
    private func selection(among choices: [ModelChoice]) -> ModelChoice {
        choices.first { $0.id == chosen }
            ?? Self.opening(among: choices)
            ?? choices[0]
    }
}

#Preview("Choose a model") {
    WelcomeView()
        .frame(width: 1200, height: 840)
        .environment(WelcomeGate(isShowing: true))
        .environment(GenerationStore.preview(state: .idle))
}

#Preview("At the window's floor") {
    WelcomeView()
        .frame(width: 880, height: 560)
        .environment(WelcomeGate(isShowing: true))
        .environment(GenerationStore.preview(state: .idle))
}

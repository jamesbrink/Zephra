import SwiftUI
import ZephraCore
import ZephraStyle

/// A picture the model made, at the top of its card.
///
/// Every sample is the same prompt at the same seed, so a row of cards compares models rather
/// than prompts; `scripts/make-samples.sh` is how the set is regenerated. A model with no
/// sample bundled — one added to the catalog before its picture was made — draws a plain
/// panel in that model's own colour instead of leaving a hole.
struct ModelSampleImage: View {
    /// The model whose sample to show.
    let choice: ModelChoice

    var body: some View {
        sample
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(shape)
            // The picture itself has nothing to announce; the two badges are facts about the
            // model and stay in the tree, so the card's own label reads them out with the rest.
            .accessibilityHidden(true)
            .overlay(alignment: .topLeading) { badge }
            .overlay(alignment: .topTrailing) {
                if choice.isRecommended { RecommendedBadge() }
            }
    }

    @ViewBuilder
    private var sample: some View {
        if let name = choice.portrait?.sampleName, NSImage(named: name) != nil {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.modelDot(choice.model.id)
                .opacity(0.22)
                .overlay {
                    Image(systemName: glyph)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                }
        }
    }

    /// The clip model says so on its sample the way it says so on a library cell: at thumbnail
    /// size a poster is indistinguishable from a picture.
    @ViewBuilder
    private var badge: some View {
        if choice.model.capabilities.producesVideo {
            VideoBadge(seconds: seconds)
        }
    }

    private var seconds: Double {
        let capabilities = choice.model.capabilities
        return Double(capabilities.defaultFrames) / Double(capabilities.frameRate)
    }

    private var glyph: String {
        choice.model.capabilities.producesVideo ? "film" : "photo"
    }

    /// Rounded at the top only: the card's own corners are below it, and a rectangle joined to
    /// the text block reads as one card rather than a picture sitting on one.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: ZephraChrome.cardRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: ZephraChrome.cardRadius,
            style: .continuous
        )
    }
}

#Preview("Samples") {
    VStack(spacing: 12) {
        ForEach(ModelChoice.all(for: MemoryBudget(physicalMemory: 48 << 30)).prefix(2)) {
            ModelSampleImage(choice: $0)
        }
    }
    .frame(width: 300)
    .padding(24)
    .background(Color.canvasBackground)
}

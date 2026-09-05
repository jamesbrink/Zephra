import SwiftUI
import ZephraCore
import ZephraEngine

/// The five things worth knowing about an image, one to a line, plus a line when it was made
/// from a picture rather than from noise and another when it was made larger from one. The
/// file's name is not one of them: it is the tooltip on Reveal in Finder, which is the only
/// place anyone needs it.
///
/// The values are formatted by `ImageFacts` in the engine, not here, because the same lines
/// describe an image on the canvas and an image in the library, and "how long it took" has
/// enough rules to be worth testing. This view's only opinions are which face each value is set
/// in and where the lines fall — which is why it takes the facts rather than either kind of
/// image, and the canvas and the library each hand it theirs.
///
/// The Reference row says only that there was one. Showing the picture would mean reading the
/// whole file to get at its second chunk, and this view is drawn for whatever is selected as
/// the selection moves; "Use as Reference" is where that read belongs, off the main actor and
/// only when it is asked for.
struct ImageFactsView: View {
    /// The lines to show, already formatted.
    let facts: ImageFacts
    /// Whether it was made from a picture rather than from noise, which adds a line.
    let edited: Bool

    var body: some View {
        VStack(spacing: 0) {
            row("Model", facts.model)
            row("Size", facts.size, style: .digits)
            row("Steps", facts.steps, style: .digits)
            row("Seed", facts.seed, style: .monospaced)
            row("Took", facts.took, style: .digits)
            if edited {
                row("Reference", "Edited from a picture")
            }
            if let upscaled = facts.upscaled {
                row("Upscaled", upscaled)
            }
            Divider()
        }
        .font(.callout)
    }

    private func row(_ key: String, _ value: String, style: KeyValueStyle = .plain) -> some View {
        VStack(spacing: 0) {
            Divider()
            KeyValueRow(key, value, style: style)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
        }
    }
}

#Preview("Facts") {
    ImageFactsView(facts: ImageFacts(PreviewImages.library(count: 1).items[0]), edited: true)
        .padding(18)
        .frame(width: 320)
}

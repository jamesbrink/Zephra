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
/// The reference row is `ReferenceFactsRow`, drawn only when `reference` names a source: a
/// thumbnail, the role's own label and the strength, read off the main actor and only for the
/// image actually on screen.
struct ImageFactsView: View {
    /// The lines to show, already formatted.
    let facts: ImageFacts
    /// The picture this one started from, and the role it played, or nil when it was made
    /// from noise.
    let reference: ReferenceFactsRow.Source?

    var body: some View {
        FactsTable {
            FactsRow("Model", facts.model)
            FactsRow("Size", facts.size, style: .digits)
            if let length = facts.length {
                FactsRow("Length", length, style: .digits)
            }
            FactsRow("Steps", facts.steps, style: .digits)
            FactsRow("Seed", facts.seed, style: .monospaced)
            FactsRow("Took", facts.took, style: .digits)
            if let reference {
                ReferenceFactsRow(facts: facts, source: reference)
            }
            if let upscaled = facts.upscaled {
                FactsRow("Upscaled", upscaled)
            }
        }
    }
}

#Preview("Facts") {
    let item = PreviewImages.library(count: 1).items[0]
    ImageFactsView(facts: ImageFacts(item), reference: .library(item, role: .startFrom))
        .padding(18)
        .frame(width: 320)
        .environment(ImageCache())
        .environment(LibraryIndex.preview(count: 1))
}

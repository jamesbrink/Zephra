import SwiftUI
import ZephraEngine

/// Where the rest of the reference pictures came from, one line each, under the row that shows
/// the first of them.
///
/// The first picture keeps `ReferenceFactsRow` — the thumbnail, the role's own label, the
/// strength and the way back to the source — and its label already says how many there were
/// ("Edited from 3 pictures"). What is missing after that is the other two names, and a name is
/// a line of the facts table rather than a second thumbnail: a column of 40-point squares down
/// the inspector would read as three separate edits, which is the thing that label exists to
/// stop saying, and reading them would mean reading the whole file once per picture.
///
/// Nothing at all for a picture made from one reference, so every model that came before this
/// one draws the inspector it always drew.
struct ReferenceOriginsList: View {
    /// The formatted facts, whose `referenceOrigins` is positional: one entry per picture, nil
    /// for one that came from a file chooser or a drop.
    let facts: ImageFacts

    var body: some View {
        if facts.referenceCount > 1 {
            ForEach(1..<facts.referenceCount, id: \.self) { index in
                FactsRow("Reference \(index + 1)", name(at: index))
            }
        }
    }

    /// The file the picture at `index` came out of, or the honest answer when it came from
    /// nowhere the library knows — a dropped file, a picture chosen from the disk.
    private func name(at index: Int) -> String {
        let origins = facts.referenceOrigins
        guard origins.indices.contains(index), let origin = origins[index] else {
            return "Not from the library"
        }
        return origin
    }
}

#Preview("Origins") {
    FactsTable {
        FactsRow("Model", "Preview Model")
        ReferenceOriginsList(facts: ImageFacts(PreviewImages.library(count: 1).items[0]))
    }
    .padding(18)
    .frame(width: 320)
}

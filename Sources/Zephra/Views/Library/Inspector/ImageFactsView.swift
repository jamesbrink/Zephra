import SwiftUI
import ZephraCore
import ZephraEngine

/// The six things worth knowing about an image, one to a line, and a seventh when it was made
/// from a picture rather than from noise.
///
/// The values are formatted by `ImageFacts` in the engine, not here, because the same six lines
/// describe an image on the canvas and an image in the library, and "how long it took" has
/// enough rules to be worth testing. This view's only opinions are which face each value is set
/// in and where the lines fall.
///
/// The Reference row says only that there was one. Showing the picture would mean reading the
/// whole file to get at its second chunk, and this view is drawn for whatever is selected as
/// the selection moves; "Use as reference" is where that read belongs, off the main actor and
/// only when it is asked for.
struct ImageFactsView: View {
    /// The image to describe.
    let item: LibraryItem

    var body: some View {
        VStack(spacing: 0) {
            row("Model", facts.model)
            row("Size", facts.size, style: .digits)
            row("Steps", facts.steps, style: .digits)
            row("Seed", facts.seed, style: .monospaced)
            row("Took", facts.took, style: .digits)
            if item.provenance.record?.referenceBytes != nil {
                row("Reference", "Edited from a picture")
            }
            row("File", facts.file, style: .monospaced)
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

    /// The catalog's name for the model when this build still ships it, and the identifier
    /// written into the file when it does not — which is the honest answer, not a blank.
    private var facts: ImageFacts {
        ImageFacts(item, modelName: item.modelID.flatMap(ModelCatalog.descriptor(id:))?.fullName)
    }
}

#Preview("Facts") {
    ImageFactsView(item: LibraryIndex.preview(count: 1).items[0])
        .padding(18)
        .frame(width: 320)
}

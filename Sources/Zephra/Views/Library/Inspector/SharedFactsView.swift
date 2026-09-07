import SwiftUI
import ZephraCore
import ZephraEngine

/// What several images have in common, and where they do not, the word "Multiple".
///
/// It is the same table as `ImageFactsView` with one rule laid over it: a value that is not the
/// same for every image in the selection is not a fact about the selection. Saying "Multiple"
/// is shorter than saying nothing and truer than showing the first one's.
struct SharedFactsView: View {
    /// The images being described together.
    let items: [LibraryItem]
    @Environment(\.seedFormat) private var seedFormat

    /// What is shown where the images disagree.
    private static let mixed = "Multiple"

    var body: some View {
        FactsTable {
            FactsRow("Model", shared { modelName(of: $0) })
            FactsRow("Size", shared { ImageFacts($0).size }, style: .digits)
            FactsRow("Steps", shared { ImageFacts($0).steps }, style: .digits)
            FactsRow("Seed", shared { ImageFacts($0, seedFormat: seedFormat).seed }, style: .monospaced)
            FactsRow("Took", shared { ImageFacts($0).took }, style: .digits)
        }
    }

    /// One fact, when every image agrees about it.
    private func shared(_ fact: (LibraryItem) -> String) -> String {
        guard let first = items.first.map(fact) else { return ImageFacts.unknown }
        return items.allSatisfy { fact($0) == first } ? first : Self.mixed
    }

    private func modelName(of item: LibraryItem) -> String {
        ImageFacts(item, modelName: item.modelID.flatMap(ModelCatalog.descriptor(id:))?.fullName).model
    }
}

#Preview("Shared facts") {
    SharedFactsView(items: Array(PreviewImages.library(count: 6).items.prefix(4)))
        .padding(18)
        .frame(width: 320)
}

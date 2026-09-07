import SwiftUI
import ZephraCore
import ZephraEngine

/// `ImageFactsView` over one library item: the catalog's name for its model when this build
/// still ships it, the identifier written into the file when it does not, and the seed spelled
/// as Settings says.
///
/// Split from `SingleImageInspector` so the spelling can be read from the environment without
/// the inspector taking a fourth stored property; the facts are formatted here and nowhere
/// else in the library's inspector.
struct LibraryFactsView: View {
    /// The image being described.
    let item: LibraryItem
    @Environment(\.seedFormat) private var seedFormat

    var body: some View {
        ImageFactsView(facts: facts, edited: item.provenance.record?.referenceBytes != nil)
    }

    private var facts: ImageFacts {
        ImageFacts(
            item, modelName: item.modelID.flatMap(ModelCatalog.descriptor(id:))?.fullName,
            seedFormat: seedFormat)
    }
}

#Preview("Library facts") {
    LibraryFactsView(item: PreviewImages.library(count: 1).items[0])
        .padding(18)
        .frame(width: 320)
}

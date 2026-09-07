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
        ImageFactsView(facts: facts, reference: reference)
    }

    private var descriptor: ModelDescriptor? { item.modelID.flatMap(ModelCatalog.descriptor(id:)) }

    private var facts: ImageFacts {
        ImageFacts(item, modelName: descriptor?.fullName, seedFormat: seedFormat)
    }

    private var reference: ReferenceFactsRow.Source? {
        guard item.provenance.record?.referenceBytes != nil else { return nil }
        let role = descriptor.map { ReferenceRole(capabilities: $0.capabilities) } ?? .reference
        return .library(item, role: role)
    }
}

#Preview("Library facts") {
    LibraryFactsView(item: PreviewImages.library(count: 1).items[0])
        .padding(18)
        .frame(width: 320)
}

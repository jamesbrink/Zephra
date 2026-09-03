import SwiftUI
import ZephraEngine

/// The column beside the grid: what is known about whatever is chosen in it.
///
/// Three states, because a selection is one of three things and each wants a different answer.
/// Nothing chosen is not an error and should not read like one; one image is the whole point of
/// the column; several is a different question — what they have in common, and what can be done
/// to all of them at once.
struct LibraryInspector: View {
    @FocusedValue(\.librarySelection) private var selection
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        Group {
            if let item = single {
                SingleImageInspector(item: item)
            } else if !ids.isEmpty {
                MultipleSelectionInspector(items: items)
            } else {
                ContentUnavailableView(
                    "No image selected",
                    systemImage: "photo",
                    description: Text("Choose an image in the grid to see how it was made.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ids: Set<LibraryItem.ID> { selection?.ids ?? [] }

    private var single: LibraryItem? {
        guard let id = selection?.single else { return nil }
        return index.item(for: id)
    }

    /// The chosen images in the order the grid is showing them, so a stack of thumbnails and a
    /// count read the same way round as the wall they came from.
    private var items: [LibraryItem] {
        index.sections.flatMap(\.items).filter { ids.contains($0.id) }
    }
}

#Preview("Nothing chosen") {
    LibraryInspector()
        .frame(width: 320, height: 620)
        .environment(PreviewImages.library(count: 38))
}

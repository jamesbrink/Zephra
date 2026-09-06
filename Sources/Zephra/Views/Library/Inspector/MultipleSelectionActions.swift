import SwiftUI
import ZephraEngine

/// What can be done to several images at once, at the foot of the inspector.
///
/// "Open in Canvas" is shown and disabled rather than left out: the button is in the same place
/// whatever is selected, and its being greyed says why — a canvas shows one picture, and there
/// is more than one here.
///
/// The variations are queued in the grid's own order, so a run of four comes back in the order
/// the four were chosen.
struct MultipleSelectionActions: View {
    /// The images the buttons act on, in the grid's order.
    let items: [LibraryItem]

    @Environment(GenerationStore.self) private var store

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Button {} label: {
                    Text("Open in Canvas").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
                .help("A canvas shows one image at a time.")
                .gridCellColumns(2)
            }
            GridRow {
                Button {
                    for item in variations { store.queueVariation(of: item) }
                } label: {
                    Text("Queue \(variations.count) Variations").frame(maxWidth: .infinity)
                }
                .disabled(variations.isEmpty || !canQueue)
                Button {
                    ImageExport.revealInFinder(files: items.exportURLs)
                } label: {
                    Text("Reveal in Finder").frame(maxWidth: .infinity)
                }
                .help("\(items.count) files")
            }
        }
        .lineLimit(1)
    }

    /// Only the ones Zephra made: an imported picture carries no request to repeat.
    private var variations: [LibraryItem] {
        items.filter { $0.provenance.record?.settings().isReadyToGenerate == true }
    }

    private var canQueue: Bool {
        store.state.acceptsGeneration || store.running != nil
    }
}

#Preview("Bulk actions") {
    MultipleSelectionActions(items: Array(PreviewImages.library(count: 6).items.prefix(4)))
        .padding(18)
        .frame(width: 320)
        .environment(GenerationStore.preview(state: .ready))
}

import SwiftUI
import ZephraEngine

/// The things to do with the image being looked at, at the foot of the inspector.
///
/// Opening is the prominent one and takes Return, because it is what the column is usually
/// leading up to: you looked at the facts, and this is the one. The rest are equals beneath it,
/// on a grid of two columns so they are the same width whatever they say; a lone last button
/// takes the whole row rather than sitting off to one side.
///
/// "Use as reference" appears only on a model that reads one, so a build running Z-Image alone
/// never shows a button that could not do anything. Opening is left out when the image is the
/// one already on the canvas, which is what the inspector beside the canvas is describing.
struct InspectorActions: View {
    /// The image the buttons act on.
    let item: LibraryItem

    @Environment(GenerationStore.self) private var store

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            if !isOnCanvas {
                GridRow {
                    LibraryOpenButton(item: item)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .gridCellColumns(2)
                }
            }
            GridRow {
                QueueVariationButton(item: item)
                Button {
                    ImageExport.revealInFinder(files: [item.url])
                } label: {
                    Text("Reveal in Finder").frame(maxWidth: .infinity)
                }
                .help(item.fileName)
            }
            GridRow {
                UpscaleButtons(item: item)
                    .gridCellColumns(2)
            }
            if store.descriptor.capabilities.supportsReferenceImage {
                GridRow {
                    UseAsReferenceButton(item: item)
                        .gridCellColumns(2)
                }
            }
        }
        .lineLimit(1)
    }

    /// Whether the canvas is already showing this file.
    private var isOnCanvas: Bool {
        store.current?.fileURL?.standardizedFileURL == item.url
    }
}

#Preview("Actions") {
    InspectorActions(item: PreviewImages.library(count: 1).items[0])
        .padding(18)
        .frame(width: 320)
        .environment(GenerationStore.preview(state: .ready))
        .environment(WorkspaceSelection(pane: .library))
}

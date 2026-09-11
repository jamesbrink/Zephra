import SwiftUI
import ZephraEngine

/// The things to do with the image being looked at, at the foot of the inspector.
///
/// Opening is the prominent one, because it is what the column is usually leading up to: you
/// looked at the facts, and this is the one. Prominent without a default-key ring: Return in
/// the library belongs to the grid's `LibraryOpenCommand`, which opens the viewer, and a second
/// owner here would answer the same key from a tag field. The rest are equals beneath it, on a
/// grid of two columns so they are the same width whatever they say; a lone last button takes
/// the whole row rather than sitting off to one side.
///
/// "Use as Reference" and "Animate" show disabled rather than hidden when the model, or this
/// build, cannot take them — the macOS convention. Opening is left out when the image is the
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
                        .gridCellColumns(2)
                }
            }
            GridRow {
                QueueVariationButton(item: item)
                Button {
                    ImageExport.revealInFinder(files: [item.exportURL])
                } label: {
                    Text("Reveal in Finder").frame(maxWidth: .infinity)
                }
                .help(item.fileName)
            }
            // An upscale makes a bigger picture out of a picture; a clip's poster is not one.
            if !item.isVideo {
                GridRow {
                    UpscaleButtons(source: .file(item.url))
                        .gridCellColumns(2)
                }
            }
            GridRow {
                ShareLink(item: item.exportURL) {
                    Text("Share…").frame(maxWidth: .infinity)
                }
                .gridCellColumns(2)
            }
            GridRow {
                UseAsReferenceButton(item: item)
                    .gridCellColumns(2)
            }
            // A row of its own: "Animate from Last Frame" does not fit half a column, and a
            // button that truncates its own verb is not a button.
            GridRow {
                AnimateButton(item: item)
                    .gridCellColumns(2)
            }
            // A clip can be carried on from where it ends; a picture has no end.
            if item.isVideo {
                GridRow {
                    ExtendClipButton(item: item)
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

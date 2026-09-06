import SwiftUI
import ZephraCore
import ZephraEngine

/// The things to do with a picture the session holds in memory, at the foot of the inspector:
/// the same four the picture's own context menu offers, as buttons of one width on a grid of
/// two columns, the way `InspectorActions` lays out the library's.
struct FreshImageActions: View {
    /// The picture the buttons act on.
    let image: GeneratedImage

    @Environment(GenerationStore.self) private var store

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                button("Export…") { ImageExport.saveAs(image) }
                button("Copy") { ImageExport.copyToPasteboard(image) }
            }
            GridRow {
                button("Reveal in Finder") { ImageExport.revealInFinder(image) }
                    .disabled(image.fileURL == nil)
                    .help(image.fileURL?.lastPathComponent ?? ImageFacts.notSaved)
                if store.descriptor.capabilities.supportsReferenceImage {
                    button("Use as Reference") { ReferenceAdoption.adopt(image, into: store) }
                }
            }
            // A clip's poster is not a picture to make larger.
            if image.settings.frames == 1 {
                GridRow {
                    UpscaleButtons(
                        source: .image(image),
                        unsavedReason: image.fileURL == nil ? ImageFacts.notSaved : nil
                    )
                        .gridCellColumns(2)
                }
            }
        }
        .lineLimit(1)
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
    }
}

#Preview("Actions") {
    FreshImageActions(image: PreviewImages.sample())
        .padding(18)
        .frame(width: 320)
        .environment(GenerationStore.preview(state: .ready))
}

import SwiftUI
import ZephraCore
import ZephraEngine

/// The things to do with a picture the session holds in memory, at the foot of the inspector:
/// the same actions the picture's own context menu offers, as buttons of one width on a grid of
/// two columns, the way `InspectorActions` lays out the library's. "Use as Reference" and
/// "Animate" show disabled rather than hidden when the model, or this build, cannot take them.
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
                    .gridCellColumns(2)
            }
            GridRow {
                button("Use as Reference") { ReferenceAdoption.adopt(image, into: store) }
                    .disabled(!canUseAsReference)
                    .help(ActionAvailability.referenceDisabledReason(
                        capabilities: store.descriptor.capabilities))
                    .gridCellColumns(2)
            }
            // A row of its own: "Animate from Last Frame" does not fit half a column, and a
            // button that truncates its own verb is not a button.
            GridRow {
                button(CommandTarget.animateTitle(forClip: image.isVideo)) {
                    ReferenceAdoption.animate(image, into: store)
                }
                .disabled(!canAnimateImage)
                .help(ActionAvailability.animateDisabledReason(
                    hasSource: ActionAvailability.hasAnimatableSource(image), store: store))
                .gridCellColumns(2)
            }
            // A clip's poster is not a picture to make larger.
            if !image.isVideo {
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

    private var canUseAsReference: Bool { store.descriptor.capabilities.supportsReferenceImage }

    /// `store.canAnimate` and whether `image` itself has bytes Animate could read — a clip
    /// whose write has not landed and whose video never reached memory either has none.
    private var canAnimateImage: Bool {
        store.canAnimate && ActionAvailability.hasAnimatableSource(image)
    }
}

#Preview("Actions") {
    FreshImageActions(image: PreviewImages.sample())
        .padding(18)
        .frame(width: 320)
        .environment(GenerationStore.preview(state: .ready))
}

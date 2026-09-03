import SwiftUI
import ZephraCore
import ZephraEngine

/// The window's whole surface: graphite ground, the picture letterboxed edge to edge on it,
/// and the engine's words over the top.
///
/// The picture runs under the prompt capsule on purpose, so its colours tint the controls.
/// It dims to 60 % while a new one is being made; progress lives in the subtitle and the capsule.
/// A single click on a finished picture toggles `WorkspaceSelection.promptTucked`, which is
/// `PromptTuckHost`'s cue to slide the floating controls out of the way.
struct CanvasView: View {
    @Environment(GenerationStore.self) private var store
    @Environment(ImageCache.self) private var cache
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        ZStack {
            Color.canvasBackground
            currentImage
            CanvasStateView()
        }
        // Only the vertical edges: the picture runs up under the title bar on purpose. It must
        // not run under the sidebar, which the split view lets content do, or the picture is
        // centred on a width that includes the column hiding its left edge.
        .ignoresSafeArea(edges: .vertical)
        // Dropping a picture on the canvas is what people will try first; it lands in the
        // same well as dropping it on the well, and does nothing for a model without one.
        .onDrop(of: ReferenceDrop.types, isTargeted: nil) { providers in
            ReferenceDrop.handle(providers, into: store)
        }
    }

    @ViewBuilder
    private var currentImage: some View {
        if let image = store.current, let bitmap = cache.fullSizeImage(for: image) {
            GeneratedImageView(bitmap: bitmap)
                .id(image.id)
                .opacity(store.state.isBusy ? 0.6 : 1)
                // Tucks the floating prompt away so the picture is the only thing on screen;
                // clicking again, or any of the ways `PromptTuckHost` listens for, brings it back.
                .onTapGesture(count: 1) { workspace.promptTucked.toggle() }
                .draggable(image)
                .contextMenu {
                    Button("Save as…") { ImageExport.saveAs(image) }
                    Button("Copy") { ImageExport.copyToPasteboard(image) }
                    Button("Reveal in Finder") { ImageExport.revealInFinder(image) }
                    if store.descriptor.capabilities.supportsReferenceImage {
                        Divider()
                        Button("Use as Reference") { store.useAsReference(image.pngData) }
                    }
                }
        }
    }
}

#Preview("Generating") {
    CanvasView()
        .frame(width: 900, height: 620)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(
            state: .generating(GenerationProgressEvent(
                phase: .denoising(step: 4, of: 9),
                fraction: 0.44,
                secondsPerStep: 2.1
            )),
            image: PreviewImages.sample()
        ))
}

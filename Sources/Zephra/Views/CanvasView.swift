import SwiftUI
import ZephraCore
import ZephraEngine

/// The pane below the toolbar strip: graphite ground, the picture letterboxed edge to edge on
/// it, and the engine's words over the top.
///
/// The picture runs under the prompt capsule on purpose, so its colours tint the controls.
/// A single click on it toggles `WorkspaceSelection.promptTucked`, which is `PromptTuckHost`'s
/// cue to slide the floating controls out of the way.
///
/// What is on the canvas depends on whether the canvas is following the run: while it is, the
/// run's own frames are, and there is nothing to right-click or drag because there is no file
/// yet. While it is not — the user went off to look at a picture, or nothing is running — the
/// picture is, at full strength even with the model working. The old dim to 60 % went with the
/// live preview: it existed to say "this is the last one, not the new one", which the frames
/// now say properly, and it made a picture you had deliberately opened look broken.
///
/// It no longer ignores the vertical safe areas: on Liquid Glass the toolbar is an opaque strip
/// (`RootView`'s `.toolbarBackgroundVisibility`), so the picture starts below it like every
/// other pane rather than running up under the title bar.
struct CanvasView: View {
    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        ZStack {
            Color.canvasBackground
            if store.isShowingRun {
                runInFlight
            } else {
                currentImage
            }
            CanvasStateView()
        }
        // Dropping a picture on the canvas is what people will try first; it lands in the
        // same well as dropping it on the well, and does nothing for a model without one.
        .onDrop(of: ReferenceDrop.types, isTargeted: nil) { providers in
            ReferenceDrop.handle(providers, into: store)
        }
    }

    /// The picture, decoded off the main actor by `SessionImage`, which holds its rectangle
    /// from the first frame and fades the pixels up when they land.
    @ViewBuilder
    private var currentImage: some View {
        if let image = store.current {
            picture(image)
                .accessibilityLabel(image.settings.frames > 1 ? "Generated clip" : "Generated image")
                // Tucks the floating prompt away so the picture is the only thing on screen;
                // clicking again, or any of the ways `PromptTuckHost` listens for, brings it back.
                .onTapGesture(count: 1) { workspace.promptTucked.toggle() }
                .draggable(image)
                .contextMenu { CanvasImageMenu(image: image) }
        }
    }

    /// The picture itself, or the clip it is the poster of once the clip is on disk: a clip
    /// that has not been saved yet shows its first frame, and starts playing when the save
    /// lands and `fileURL` arrives.
    @ViewBuilder
    private func picture(_ image: GeneratedImage) -> some View {
        if image.settings.frames > 1, let file = image.fileURL {
            ClipPlayerView(url: VideoSidecar.url(beside: file), paused: store.running != nil)
                .aspectRatio(
                    CGFloat(image.settings.size.width) / CGFloat(image.settings.size.height),
                    contentMode: .fit)
        } else {
            SessionImage(request: .full(image))
        }
    }

    /// The run being watched. Until its first frame arrives there is only the shape it will
    /// fill, so `RunPlaceholderView` sits in it: something is happening, and this is what. It
    /// goes the moment there is a picture to look at instead; the step count itself stays on
    /// the capsule's edge and in the toolbar, where it already was.
    private var runInFlight: some View {
        LivePreviewView(preview: store.livePreview, size: runSize)
            .overlay {
                if store.livePreview == nil {
                    RunPlaceholderView(phase: store.state.generationPhase)
                }
            }
            .onTapGesture(count: 1) { workspace.promptTucked.toggle() }
    }

    /// The shape the run is making. `settings` stands in for the moment between the queue
    /// handing a run over and the store publishing it, when both say the same thing anyway.
    private var runSize: ImageSize { store.running?.settings.size ?? store.settings.size }
}

#Preview("Following the run") {
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
            running: InterfacePreview.queuedRun(of: 1).first,
            livePreview: PreviewImages.frame()
        ))
}

#Preview("Watching something else while it runs") {
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
            image: PreviewImages.sample(),
            running: InterfacePreview.queuedRun(of: 1).first,
            livePreview: PreviewImages.frame(),
            following: false
        ))
}

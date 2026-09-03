import SwiftUI
import ZephraEngine

/// Everything that floats over the picture, stacked up from the bottom edge: a save notice
/// when there is one, the caption of the image being looked at, the prompt capsule, and the
/// images this run has made.
struct CanvasOverlay: View {
    @AppStorage(AppSettings.runStripVisible)
    private var runStripVisible = AppSettings.initialRunStripVisible

    var body: some View {
        VStack(spacing: 14) {
            SaveNotice()
            PromptCaption()
            PromptCapsule()
            if runStripVisible { RunStrip() }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .frame(maxWidth: 736)
    }
}

#Preview("Overlay") {
    CanvasOverlay()
        .padding(.top, 60)
        .frame(width: 900)
        .background(Color.canvasBackground)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready, image: PreviewImages.sample()))
}

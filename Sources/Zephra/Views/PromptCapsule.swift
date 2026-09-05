import SwiftUI
import ZephraEngine

/// The one floating control surface, made of system material so the picture behind it tints
/// every control on it. Step segments ride its top edge; the prompt and its settings sit inside.
///
/// The segments are inset by the capsule's own radius: the panel clips to its rounded shape,
/// and a bar run edge to edge lost its first and last segments to the corners' curve.
struct PromptCapsule: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepSegments(progress: store.stepProgress)
                .padding(.horizontal, ZephraChrome.capsuleRadius)
            // One width for the prompt, the divider and the settings, so the reference well
            // lines up with the Generate button even when the settings row is the widest.
            SharedWidthRows(spacing: 12) {
                PromptRow()
                Divider()
                PromptControls()
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 12)
        }
        .chromePanel(.floating)
        .frame(maxWidth: CanvasOverlay.maxWidth)
    }
}

#Preview("Capsule") {
    PromptCapsule()
        .padding(30)
        .frame(width: 900)
        .background(Color.canvasBackground)
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready))
}

#Preview("Capsule for a guided model") {
    PromptCapsule()
        .padding(30)
        .frame(width: 900)
        .background(Color.canvasBackground)
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.guided))
}

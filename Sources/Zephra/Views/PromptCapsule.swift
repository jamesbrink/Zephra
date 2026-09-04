import SwiftUI
import ZephraEngine

/// The one floating control surface, made of system material so the picture behind it tints
/// every control on it. Step segments ride its top edge; the prompt and its settings sit inside.
struct PromptCapsule: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepSegments(
                total: store.settings.steps,
                completed: store.state.denoisingProgress?.step ?? 0,
                isRunning: store.state.denoisingProgress != nil
            )
            // One width for the prompt, the divider and the settings, so the reference well
            // lines up with the Generate button even when the settings row is the widest.
            SharedWidthRows(spacing: 12) {
                PromptRow()
                Divider()
                controls
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 12)
        }
        .chromePanel(.floating)
        // Wide enough for the settings, the batch count, and a Generate button that spells out
        // its shortcut, without the row overflowing the panel it is drawn in. The overlay above
        // allows 736; a settings row that needs more widens the whole capsule, prompt included.
        .frame(maxWidth: 736)
    }

    private var controls: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ControlsRow()
            Spacer(minLength: 12)
            BatchCountControl()
            StopButton()
            GenerateButton()
        }
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

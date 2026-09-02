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
            VStack(alignment: .leading, spacing: 12) {
                PromptEditor()
                NegativePromptField()
                Divider()
                HStack(alignment: .bottom, spacing: 12) {
                    ControlsRow()
                    Spacer(minLength: 12)
                    QueueChip()
                    StopButton()
                    GenerateButton()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 12)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 22, y: 8)
        .frame(maxWidth: 680)
    }
}

#Preview("Capsule") {
    PromptCapsule()
        .padding(30)
        .frame(width: 900)
        .background(Color.canvasBackground)
        .environment(GenerationStore.preview(state: .ready))
}

#Preview("Capsule for a guided model") {
    PromptCapsule()
        .padding(30)
        .frame(width: 900)
        .background(Color.canvasBackground)
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.guided))
}

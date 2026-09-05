import SwiftUI
import ZephraEngine

/// What the picture on the canvas was asked for, when that is no longer what is in the prompt
/// field. Absent otherwise: repeating the field back at you is not a caption.
struct PromptCaption: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        if let image = store.current, !store.state.isBusy,
           image.settings.prompt != store.settings.prompt {
            Text(image.settings.prompt)
                .font(.callout)
                .fontDesign(.serif)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(ZephraChrome.captionShadowOpacity), radius: 6)
                .padding(.horizontal, 24)
        }
    }
}

#Preview("Caption") {
    PromptCaption()
        .padding()
        .frame(width: 500)
        .background(Color.canvasBackground)
        .environment(GenerationStore.preview(
            state: .ready,
            image: PreviewImages.sample(prompt: "A harbour in the rain, long exposure")
        ))
}

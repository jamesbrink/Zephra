import SwiftUI
import ZephraEngine

/// The optional inputs under the prompt: what to avoid, and a picture to edit. Each shows only
/// for a model that reads it, and this row is what keeps two absent children from leaving a
/// gap in the capsule.
struct PromptInputsRow: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        let capabilities = store.descriptor.capabilities
        if capabilities.supportsNegativePrompt || capabilities.supportsReferenceImage {
            HStack(alignment: .top, spacing: 12) {
                NegativePromptField()
                Spacer(minLength: 0)
                ReferenceImageWell()
            }
        }
    }
}

#Preview("Inputs for an editing model") {
    PromptInputsRow()
        .padding()
        .frame(width: 520)
        .environment(ImageCache())
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.editing))
}

import SwiftUI
import ZephraStyle

/// A full-width chooser lets model names and the Mac's verdict wrap at every text size.
///
/// The label names the model chosen and says whether the destination Mac has it in memory, since
/// under on-demand loading a Mac stands ready with a model chosen and nothing read in.
struct ModelMenu: View {
    @Environment(GenerationDispatch.self) private var dispatch
    @Environment(PromptDraft.self) private var draft
    @State private var isChoosing = false

    var body: some View {
        if !dispatch.models.isEmpty {
            Button { isChoosing = true } label: {
                HStack(spacing: 6) {
                    ModelDot(draft.modelID)
                    Text(dispatch.modelLabel(for: draft.modelID))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityLabel("Model")
            .sheet(isPresented: $isChoosing) { ModelPickerSheet() }
        }
    }
}

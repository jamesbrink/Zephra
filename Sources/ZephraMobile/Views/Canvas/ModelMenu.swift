import SwiftUI
import ZephraStyle

/// A full-width chooser lets model names and the Mac's verdict wrap at every text size.
struct ModelMenu: View {
    @Environment(GenerationDispatch.self) private var dispatch
    @Environment(PromptDraft.self) private var draft
    @State private var isChoosing = false

    var body: some View {
        if !dispatch.models.isEmpty {
            Button { isChoosing = true } label: {
                HStack(spacing: 6) {
                    ModelDot(draft.modelID)
                    Text(dispatch.models.first { $0.id == draft.modelID }?.label ?? "Choose Model")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityLabel("Model")
            .sheet(isPresented: $isChoosing) { ModelPickerSheet() }
        }
    }
}

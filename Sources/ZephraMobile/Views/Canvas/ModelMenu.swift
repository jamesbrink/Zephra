import SwiftUI
import ZephraLinkClient
import ZephraLinkProtocol
import ZephraStyle

/// Chooses the phone's draft model without changing any Mac's canvas.
/// Memory and acquisition verdicts remain each host's own; Auto can choose a model
/// when at least one enabled host can hold it.
struct ModelMenu: View {
    @Environment(GenerationDispatch.self) private var dispatch
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        if !dispatch.models.isEmpty {
            Menu {
                AdoptHostSettings()
                ForEach(dispatch.models) { model in
                    Button { choose(model) } label: {
                        row(model, note: dispatch.modelReadiness(model.id))
                    }
                    .disabled(!dispatch.canChooseModel(model.id))
                }
            } label: {
                HStack(spacing: 6) {
                    ModelDot(draft.modelID)
                    Text(dispatch.models.first { $0.id == draft.modelID }?.label ?? "Choose Model").font(.callout)
                }
            }
            .accessibilityLabel("Model")
        }
    }

    @ViewBuilder private func row(_ model: ModelSummary, note: String?) -> some View {
        let title = note.map { "\(model.label) · \($0)" } ?? model.label
        if model.id == draft.modelID {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func choose(_ model: ModelSummary) { draft.choose(model) }
}

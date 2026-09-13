import SwiftUI
import ZephraLinkClient
import ZephraLinkProtocol
import ZephraStyle

/// Picks which model the Mac runs next, and says what choosing one would cost.
///
/// The Mac's `ModelMenu`, over the models the snapshot lists rather than over the catalog: the
/// phone has no catalog, and a model the Mac cannot run is a model it did not send. The
/// availability line under a name is the Mac's own sentence, written once there and shown here
/// unchanged.
///
/// Choosing is two things at once and deliberately so: the Mac is told, so its own canvas
/// follows, and the draft takes the new model's schedule, so the controls under the prompt are
/// the ones that model actually has.
struct ModelMenu: View {
    @Environment(GenerationDispatch.self) private var dispatch
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        if !dispatch.models.isEmpty {
            Menu {
                AdoptHostSettings()
                ForEach(dispatch.models) { model in
                    Button {
                        choose(model)
                    } label: {
                        row(model, note: readiness(model.id))
                    }
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

    private func readiness(_ id: String) -> String {
        let count = dispatch.hosts.hosts.filter { $0.preference.enabled && $0.client.connection.isLive && $0.client.snapshot?.availability[id]?.kind == .available }.count
        return "Ready on \(count) Macs"
    }
    private func choose(_ model: ModelSummary) { draft.choose(model) }
}

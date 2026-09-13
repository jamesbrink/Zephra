import SwiftUI
import ZephraLinkClient
import ZephraLinkProtocol
import ZephraStyle

/// Picks which model the Mac runs next, and says what choosing one would cost.
///
/// The Mac's `ModelMenu`, over the models the snapshot lists rather than over the catalog: the
/// phone has no catalog. Every note under a name is the Mac's own sentence, written once there
/// and shown here unchanged — what it would cost to obtain, and what it would cost to hold.
///
/// Two ways a row greys, and both are the Mac's answer rather than this view's: a model that
/// cannot be obtained at all, and one this Mac has not the memory to hold, which is never
/// loaded and never downloaded and so is not something to offer a press of.
///
/// Choosing is two things at once and deliberately so: the Mac is told, so its own canvas
/// follows, and the draft takes the new model's schedule, so the controls under the prompt are
/// the ones that model actually has.
struct ModelMenu: View {
    @Environment(LinkClient.self) private var client
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        if let snapshot = client.snapshot {
            Menu {
                ForEach(snapshot.models) { model in
                    let availability = snapshot.availability[model.id]
                    Button {
                        choose(model)
                    } label: {
                        row(model, note: model.note(availability: availability))
                    }
                    .disabled(!model.isChoosable(availability: availability))
                }
            } label: {
                HStack(spacing: 6) {
                    ModelDot(draft.modelID)
                    Text(current(in: snapshot)).font(.callout)
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

    /// What the button says: the model the draft names, as the Mac spells it.
    private func current(in snapshot: StateSnapshot) -> String {
        snapshot.models.first { $0.id == draft.modelID }?.label ?? snapshot.model.label
    }

    private func choose(_ model: ModelSummary) {
        guard model.id != draft.modelID else { return }
        draft.choose(model)
        Task { try? await client.switchModel(model.id) }
    }
}

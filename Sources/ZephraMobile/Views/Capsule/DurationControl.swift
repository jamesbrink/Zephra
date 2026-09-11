import SwiftUI
import ZephraCore
import ZephraLinkProtocol

/// How long the clip should run, on a model that makes clips: a menu of whole seconds, each
/// standing for the frame count on the model's own ladder nearest to it.
///
/// `ClipLength` is the rule, in `ZephraCore`, and it is the Mac's menu exactly: one pass by the
/// second, then the longer clips the Mac makes as a chain of passes. The Mac plans that chain
/// itself when the request lands (`ChainPlan` in `GenerationStore.enqueue`), so the phone sends
/// the whole length and nothing here has to know how a chain is run.
struct DurationControl: View {
    /// What the model in force will accept.
    let capabilities: CapabilitiesSummary
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        let model = capabilities.capabilities
        Menu {
            ForEach(ClipLength.choices(model), id: \.self) { frames in
                Button {
                    draft.settings.frames = frames
                } label: {
                    let title = ClipLength.label(frames: frames, capabilities: model)
                    if frames == draft.settings.frames {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            Text(ClipLength.label(frames: draft.settings.frames, capabilities: model))
                .font(.callout)
                .monospacedDigit()
        }
        .accessibilityLabel("Clip length")
    }
}

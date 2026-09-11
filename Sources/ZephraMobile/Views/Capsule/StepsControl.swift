import SwiftUI
import ZephraLinkProtocol

/// How many denoising steps the Mac should run. More steps means more detail and more seconds.
///
/// A stepper rather than the Mac's slider: a phone's thumb is not a mouse, and the counts that
/// matter are a handful apart. The bounds are checked here as well as in `ControlsGrid`, for
/// the reason the Mac's control gives — the body can be re-evaluated with a new model's bounds
/// before the row above takes the control away, and a control over a single value is not a
/// control.
struct StepsControl: View {
    /// What the model in force will accept.
    let capabilities: CapabilitiesSummary
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        if capabilities.capabilities.adjustsSteps {
            let bounds = capabilities.stepBounds
            Stepper(value: value, in: bounds) {
                Text("\(draft.settings.steps)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Denoising steps")
            .accessibilityValue("\(draft.settings.steps)")
        }
    }

    /// The step count, held inside the model's bounds whatever it arrived as.
    private var value: Binding<Int> {
        Binding(
            get: {
                min(max(draft.settings.steps, capabilities.stepBounds.lowerBound),
                    capabilities.stepBounds.upperBound)
            },
            set: { draft.settings.steps = $0 })
    }
}

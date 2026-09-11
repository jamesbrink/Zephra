import SwiftUI
import ZephraLinkProtocol

/// How strongly the prompt overrides the model's own priors.
///
/// Distilled models run at a fixed guidance and never show this; the bounds are read here as
/// well as in `ControlsGrid` because a `Slider` over a single value stops the app, which is
/// how the Mac once crashed on a model switch.
struct GuidanceControl: View {
    /// What the model in force will accept.
    let capabilities: CapabilitiesSummary
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        if capabilities.capabilities.adjustsGuidance {
            HStack(spacing: 10) {
                Slider(value: value, in: capabilities.guidanceBounds, step: 0.5)
                Text(draft.settings.guidance, format: .number.precision(.fractionLength(1)))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32, alignment: .trailing)
            }
            .accessibilityLabel("Prompt guidance")
        }
    }

    /// Guidance, held inside the model's bounds whatever it arrived as: a slider handed a
    /// value outside its range is the same precondition failure as one over a single value.
    private var value: Binding<Double> {
        Binding(
            get: {
                min(max(draft.settings.guidance, capabilities.guidanceBounds.lowerBound),
                    capabilities.guidanceBounds.upperBound)
            },
            set: { draft.settings.guidance = $0 })
    }
}

import SwiftUI
import ZephraEngine

/// How strongly the prompt overrides the model's own priors, as a slider with its value beside
/// it. Distilled models like Z-Image Turbo run at a fixed guidance and never show this.
///
/// The check on the bounds is repeated here even though `ControlsRow` only places this view
/// for a model that adjusts guidance: when the model changes, this body can be re-evaluated
/// with the new bounds before the row removes it, and a `Slider` over a single value stops the
/// app. Read the capabilities, not the bounds, so the guard cannot drift from the row's.
struct GuidanceControl: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let capabilities = store.descriptor.capabilities
        if capabilities.adjustsGuidance {
            HStack(spacing: 10) {
                Slider(value: $store.settings.guidance, in: capabilities.guidanceBounds, step: 0.5)
                    .controlSize(.small)
                    .frame(width: 110)
                Text(store.settings.guidance, format: .number.precision(.fractionLength(1)))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 26, alignment: .leading)
            }
            .help("Prompt guidance")
            .accessibilityLabel("Prompt guidance")
        }
    }
}

#Preview("Guidance") {
    GuidanceControl()
        .padding()
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.guided))
}

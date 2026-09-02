import SwiftUI
import ZephraEngine

/// How strongly the prompt overrides the model's own priors, as a slider with its value beside
/// it. Distilled models like Z-Image Turbo run at a fixed guidance and never show this.
struct GuidanceControl: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let bounds = store.descriptor.capabilities.guidanceBounds
        HStack(spacing: 10) {
            Slider(value: $store.settings.guidance, in: bounds, step: 0.5)
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

#Preview("Guidance") {
    GuidanceControl()
        .padding()
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.guided))
}

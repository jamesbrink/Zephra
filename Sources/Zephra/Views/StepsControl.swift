import SwiftUI
import ZephraEngine

/// How many denoising steps to run, as a slider with its value beside it. More steps means
/// more detail and more seconds; the model's own bounds cap the range.
struct StepsControl: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let bounds = store.descriptor.capabilities.stepBounds
        HStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { Double(store.settings.steps) },
                    set: { store.settings.steps = Int($0.rounded()) }
                ),
                in: Double(bounds.lowerBound)...Double(bounds.upperBound),
                step: 1
            )
            .controlSize(.small)
            // Flexible rather than fixed, so a narrow window takes its space out of the slider
            // instead of out of the Generate button's label.
            .frame(minWidth: 80, maxWidth: 130)
            Text("\(store.settings.steps)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 18, alignment: .leading)
        }
        .help("Denoising steps")
        .accessibilityLabel("Denoising steps")
        .accessibilityValue("\(store.settings.steps)")
    }
}

#Preview("Steps") {
    StepsControl()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}

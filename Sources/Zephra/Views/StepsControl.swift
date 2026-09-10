import SwiftUI
import ZephraEngine

/// How many denoising steps to run, as a slider with its value beside it. More steps means
/// more detail and more seconds; the model's own bounds cap the range.
///
/// The check on the bounds is repeated here even though `ControlsRow` only places this view
/// for a model that adjusts its steps, for the reason `GuidanceControl` gives: when the model
/// changes, this body can be re-evaluated with the new bounds before the row removes it, and a
/// `Slider` over a single value is a precondition failure. Choosing LTX-2.5, whose eight steps
/// are the checkpoint's, was the first switch to a model with one legal step count, and it
/// stopped the app here.
struct StepsControl: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let capabilities = store.descriptor.capabilities
        if capabilities.adjustsSteps {
            let bounds = capabilities.stepBounds
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
                // Flexible rather than fixed, so a narrow window takes its space out of the
                // slider instead of out of the Generate button's label.
                .frame(minWidth: 80, maxWidth: 130)
                Text("\(store.settings.steps)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18, alignment: .leading)
            }
            .help("Denoising steps. Fewer is quicker; more adds detail.")
            .accessibilityLabel("Denoising steps")
            .accessibilityValue("\(store.settings.steps)")
        }
    }
}

#Preview("Steps") {
    StepsControl()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}

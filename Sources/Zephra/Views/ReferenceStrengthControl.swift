import SwiftUI
import ZephraEngine

/// How much of the reference picture survives, as a slider with its value beside it.
///
/// Shown only while there is a picture to apply it to, and only for a model that starts from a
/// noised copy of one. FLUX.2 klein attends to the picture as extra tokens and renders the whole
/// schedule from noise, so it declares a single legal strength and never shows this — the same
/// way a distilled model hides the guidance slider.
///
/// Lower keeps more of the picture: the strength buys that share of the model's steps, and the
/// ones it does not buy are the ones that would have moved furthest from where it started.
struct ReferenceStrengthControl: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let bounds = store.descriptor.capabilities.referenceStrengthBounds
        HStack(spacing: 10) {
            Slider(value: $store.settings.referenceStrength, in: bounds, step: 0.05)
                .controlSize(.small)
                .frame(width: 110)
            Text(store.settings.referenceStrength, format: .number.precision(.fractionLength(2)))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, alignment: .leading)
        }
        .help("How much of the picture to keep. Lower keeps more of it.")
        .accessibilityLabel("Reference strength")
    }
}

#Preview("Strength") {
    let store = GenerationStore.preview(state: .ready, descriptor: PreviewModel.editing)
    store.useAsReference(PreviewImages.referencePNG())
    return ReferenceStrengthControl()
        .padding()
        .environment(store)
}

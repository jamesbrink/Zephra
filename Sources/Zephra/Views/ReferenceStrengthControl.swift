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
///
/// The bounds are checked here as well as in `ControlsRow`, for the reason `GuidanceControl`
/// gives: switching from Z-Image to klein with a picture in the well re-evaluated this body
/// with klein's single legal value before the row took the control away, and a `Slider` over
/// `1...1` is a precondition failure, which is how the app crashed on a model switch.
struct ReferenceStrengthControl: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let capabilities = store.descriptor.capabilities
        if capabilities.adjustsReferenceStrength {
            HStack(spacing: 10) {
                Slider(
                    value: $store.settings.referenceStrength,
                    in: capabilities.referenceStrengthBounds, step: 0.05
                )
                .controlSize(.small)
                // Flexible, like the steps slider: with strength showing the row is at the
                // capsule's width, and a fixed slider would push it past the prompt above.
                .frame(minWidth: 70, maxWidth: 110)
                Text(store.settings.referenceStrength, format: .number.precision(.fractionLength(2)))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32, alignment: .leading)
            }
            .help(ReferenceRole(capabilities: capabilities).strengthHelp)
            .accessibilityLabel("Reference strength")
        }
    }
}

#Preview("Strength") {
    let store = GenerationStore.preview(state: .ready, descriptor: PreviewModel.editing)
    store.useAsReference(PreviewImages.referencePNG())
    return ReferenceStrengthControl()
        .padding()
        .environment(store)
}

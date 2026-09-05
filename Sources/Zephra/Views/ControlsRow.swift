import SwiftUI
import ZephraEngine

/// The settings under the prompt, each under a small label: size, steps, guidance, strength,
/// seed. Everything that changes the next image, nothing that does not — so guidance appears
/// only for models that respond to it, never for a distilled one like Z-Image Turbo, and
/// strength only while a picture is in the well on a model that starts from a noised copy.
struct ControlsRow: View {
    var wraps = false
    @Environment(GenerationStore.self) private var store

    var body: some View {
        layout {
            ControlLabel("Size") { SizeMenu() }
            ControlLabel("Steps") { StepsControl() }
            if showsGuidance {
                ControlLabel("Guidance") { GuidanceControl() }
            }
            if showsReferenceStrength {
                ControlLabel("Strength") { ReferenceStrengthControl() }
            }
            ControlLabel("Seed") { SeedControl() }
        }
        .disabled(store.state.isBusy)
    }

    private var layout: AnyLayout {
        wraps
            ? AnyLayout(WrappingHStack(horizontalSpacing: 18, verticalSpacing: 12))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 18))
    }

    /// A model with a single legal guidance value has nothing to offer here.
    private var showsGuidance: Bool {
        store.descriptor.capabilities.adjustsGuidance
    }

    /// Strength says how much of a picture survives, so it means nothing without one, and
    /// nothing on a model that conditions on the picture instead of starting from it.
    private var showsReferenceStrength: Bool {
        store.settings.referenceImage != nil
            && store.descriptor.capabilities.adjustsReferenceStrength
    }
}

#Preview("Controls") {
    ControlsRow()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}

#Preview("Controls with guidance") {
    ControlsRow()
        .padding()
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.guided))
}

#Preview("Controls with a picture in the well") {
    let store = GenerationStore.preview(state: .ready, descriptor: PreviewModel.editing)
    store.useAsReference(PreviewImages.referencePNG())
    return ControlsRow()
        .padding()
        .environment(store)
}

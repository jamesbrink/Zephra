import SwiftUI
import ZephraEngine

/// The settings under the prompt, each under a small label: size, steps, guidance, strength,
/// seed. Everything that changes the next image, nothing that does not — so guidance appears
/// only for models that respond to it, never for a distilled one like Z-Image Turbo, and
/// strength only while a picture is in the well on a model that starts from a noised copy.
struct ControlsRow: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
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

    /// A model with a single legal guidance value has nothing to offer here.
    private var showsGuidance: Bool {
        let bounds = store.descriptor.capabilities.guidanceBounds
        return bounds.lowerBound < bounds.upperBound
    }

    /// Strength says how much of a picture survives, so it means nothing without one, and
    /// nothing on a model that conditions on the picture instead of starting from it.
    private var showsReferenceStrength: Bool {
        let bounds = store.descriptor.capabilities.referenceStrengthBounds
        return store.settings.referenceImage != nil && bounds.lowerBound < bounds.upperBound
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

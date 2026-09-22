import SwiftUI
import ZephraEngine

/// The settings under the prompt, each under a small label: size, steps, length, guidance,
/// strength, seed. Everything that changes the next image, nothing that does not — so guidance
/// appears only for models that respond to it, never for a distilled one like Z-Image Turbo,
/// steps only where the count is a choice (LTX-2.5's ladder is fixed), length only for a model
/// that makes clips, and strength only while a picture is in the well on a model that starts
/// from a noised copy.
///
/// Live while the model works, like the prompt above them: a run carries its own settings
/// (`QueuedGeneration`), so nothing here can reach the one in flight, and Generate queues the
/// next one with whatever the row says. The row once greyed out for every busy state, which
/// left a person able to type the next prompt but not to move the next strength.
struct ControlsRow: View {
    var wraps = false
    @Environment(GenerationStore.self) private var store

    var body: some View {
        layout {
            ControlLabel("Size") { SizeMenu() }
            if store.descriptor.capabilities.adjustsSteps {
                ControlLabel("Steps") { StepsControl() }
            }
            if store.descriptor.capabilities.adjustsFrames {
                ControlLabel("Length") { DurationControl() }
            }
            if showsGuidance {
                ControlLabel("Guidance") { GuidanceControl() }
            }
            if showsReferenceStrength {
                ControlLabel("Strength") { ReferenceStrengthControl() }
            }
            ControlLabel("Seed") { SeedControl() }
        }
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
        !store.settings.referenceImages.isEmpty
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

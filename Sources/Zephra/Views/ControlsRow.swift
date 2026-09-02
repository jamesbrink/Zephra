import SwiftUI
import ZephraEngine

/// The settings under the prompt, each under a small label: size, steps, guidance, seed.
/// Everything that changes the next image, nothing that does not — so guidance appears only
/// for models that respond to it, and never for a distilled one like Z-Image Turbo.
struct ControlsRow: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            ControlLabel("Size") { SizeMenu() }
            ControlLabel("Steps") { StepsControl() }
            if showsGuidance {
                ControlLabel("Guidance") { GuidanceControl() }
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

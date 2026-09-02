import SwiftUI
import ZephraEngine

/// The settings under the prompt, always visible and each under a small label: size, steps,
/// seed. Everything that changes the next image, nothing that does not.
struct ControlsRow: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            ControlLabel("Size") { SizeMenu() }
            ControlLabel("Steps") { StepsControl() }
            ControlLabel("Seed") { SeedControl() }
        }
        .disabled(store.state.isBusy)
    }
}

#Preview("Controls") {
    ControlsRow()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}

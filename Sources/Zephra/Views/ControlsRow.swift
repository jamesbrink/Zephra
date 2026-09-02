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

/// A small caption over a control, so the row reads as labelled fields rather than loose chips.
struct ControlLabel<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.tertiary)
            content
                .frame(height: 26)
        }
    }
}

#Preview("Controls") {
    ControlsRow()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}

import SwiftUI
import ZephraEngine

/// The line of settings under the prompt: size, steps, seed. Everything that changes the
/// next image, and nothing that does not.
struct SettingsChips: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        HStack(spacing: 1) {
            SizeMenu(showsIndicator: false)
            separator
            StepsChip()
            separator
            SeedChip()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .disabled(isLocked)
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
    }

    private var isLocked: Bool {
        switch store.state {
        case .generating, .cancelling: true
        default: false
        }
    }
}

#Preview("Chips") {
    SettingsChips()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}

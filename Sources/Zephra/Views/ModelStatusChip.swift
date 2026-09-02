import SwiftUI
import ZephraEngine

/// The dot and word in the toolbar that say what the engine is doing, in two syllables.
struct ModelStatusChip: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(store.state.statusLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .help(store.descriptor.fullName)
        .accessibilityElement(children: .combine)
    }

    private var dotColor: Color {
        switch store.state {
        case .failed: .red
        case .ready: .secondary
        default: .safelight
        }
    }
}

#Preview("Status") {
    VStack(alignment: .leading, spacing: 10) {
        ModelStatusChip().environment(GenerationStore.preview(state: .ready))
        ModelStatusChip().environment(GenerationStore.preview(state: .warmingUp))
    }
    .padding()
}

import SwiftUI
import ZephraCore
import ZephraEngine

/// Picks the output dimensions from the sizes this model actually accepts.
struct SizeMenu: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        Menu {
            ForEach(store.descriptor.capabilities.sizePresets, id: \.self) { size in
                Button {
                    store.settings.size = size
                } label: {
                    if size == store.settings.size {
                        Label(size.label, systemImage: "checkmark")
                    } else {
                        Text(size.label)
                    }
                }
            }
        } label: {
            Text(store.settings.size.label)
                .font(.callout)
                .monospacedDigit()
        }
        .menuStyle(.button)
        .menuIndicator(.visible)
        .buttonStyle(.accessoryBar)
        .fixedSize()
        .help("Output size")
        .accessibilityLabel("Output size")
    }
}

#Preview("Size") {
    SizeMenu()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}

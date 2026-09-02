import SwiftUI
import ZephraEngine

/// The noise seed, shown in full so an image can be reproduced, with a die for a fresh one.
struct SeedChip: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        HStack(spacing: 2) {
            Text("seed \(String(store.settings.seed))")
                .monospaced()
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 168, alignment: .leading)
                .help("Seed \(String(store.settings.seed))")
            Button {
                store.randomizeSeed()
            } label: {
                Image(systemName: "die.face.5")
            }
            .buttonStyle(.accessoryBar)
            .help("Pick a new seed")
            .accessibilityLabel("Pick a new seed")
        }
        .font(.callout)
    }
}

#Preview("Seed") {
    SeedChip()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}

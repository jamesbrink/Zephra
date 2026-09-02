import SwiftUI
import ZephraEngine

/// The noise seed in a short readable form, a shuffle for a fresh one, and a lock that keeps
/// it across runs. The full value lives in the tooltip and in every saved file's name.
struct SeedControl: View {
    @Environment(GenerationStore.self) private var store
    @AppStorage(AppSettings.randomizeSeedEachRun) private var randomizeEachRun = AppSettings.initialRandomizeSeedEachRun

    var body: some View {
        HStack(spacing: 4) {
            Text(store.settings.seed.shortSeedLabel)
                .font(.callout)
                .monospaced()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .help("Seed \(String(store.settings.seed))")
            Button {
                store.randomizeSeed()
            } label: {
                Image(systemName: "shuffle")
            }
            .buttonStyle(.accessoryBar)
            .help("Pick a new seed")
            .accessibilityLabel("Pick a new seed")
            Toggle(isOn: Binding(get: { !randomizeEachRun }, set: { randomizeEachRun = !$0 })) {
                Image(systemName: randomizeEachRun ? "lock.open" : "lock.fill")
            }
            .toggleStyle(.button)
            .buttonStyle(.accessoryBar)
            .help(randomizeEachRun ? "Each run picks a new seed. Click to keep this one." : "Keeping this seed for every run.")
            .accessibilityLabel("Keep seed")
        }
    }
}

#Preview("Seed") {
    SeedControl()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}

import SwiftUI
import ZephraEngine

/// The noise seed as `SeedLabel` spells it, a shuffle for a fresh one, and a lock that keeps
/// it across runs. The full value lives in the tooltip and in every saved file's name, and a
/// click on the label opens `SeedEntryPopover` to type one in.
struct SeedControl: View {
    @Environment(GenerationStore.self) private var store
    @AppStorage(AppSettings.randomizeSeedEachRun) private var randomizeEachRun = AppSettings.initialRandomizeSeedEachRun
    @State private var isEntering = false

    var body: some View {
        HStack(spacing: 4) {
            SeedLabel(isEntering: $isEntering)
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

import SwiftUI
import ZephraCore
import ZephraEngine

/// Whether the last step of a generation, decoding the latent into pixels, runs in tiles.
///
/// This is the one setting that trades exactness for memory, so it says what the trade costs
/// and then gets out of the way: Automatic tiles only for a model that would otherwise page on
/// this Mac. The choice reaches the runtime as the picker moves, not on relaunch.
struct VAETilingControl: View {
    @Environment(\.inferenceRuntime) private var runtime
    @Environment(GenerationStore.self) private var store
    @AppStorage(AppSettings.vaeTiling) private var mode = AppSettings.initialVAETiling

    var body: some View {
        Picker("Tiled VAE decode", selection: $mode) {
            ForEach(VAETilingMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        Text("Tiling the decode saves about 6 GB of peak memory at 1024 pixels, and the image "
            + "comes back differing by roughly 1 part in 255, with no visible seam. Automatic "
            + "tiles only when the chosen model would otherwise page on this Mac.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .onChange(of: mode, initial: true) { apply() }
            .onChange(of: store.descriptor) { apply() }
    }

    private func apply() {
        let policy = VAETilingPolicy(
            mode: mode,
            physicalMemory: ProcessInfo.processInfo.physicalMemory
        )
        runtime?.setVAETileSize(policy.tileSize(for: store.descriptor))
    }
}

#Preview("VAE tiling") {
    Form { Section("Image decoding") { VAETilingControl() } }
        .formStyle(.grouped)
        .frame(width: 480)
        .environment(GenerationStore.preview(state: .ready))
}

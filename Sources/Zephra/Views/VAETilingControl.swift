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
        Text(caption)
            .font(.caption)
            .foregroundStyle(.secondary)
            .onChange(of: mode, initial: true) { apply() }
            .onChange(of: store.descriptor) { apply() }
    }

    /// What tiling costs and saves for the model that is actually selected. The saving is the
    /// difference between two measured numbers in the descriptor, so it stays true as models are
    /// added rather than quoting whichever one it was written against.
    private var caption: String {
        let model = store.descriptor
        let saved = Double(model.peakBytes - model.tiledPeakBytes) / 1_000_000_000
        return String(
            format: "Tiling the decode saves about %.1f GB of peak memory for %@ at its default "
                + "size, and the image comes back differing by about one part in 255, with no "
                + "visible seam. Automatic tiles only when the chosen model would otherwise "
                + "page on this Mac.",
            saved,
            model.fullName
        )
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

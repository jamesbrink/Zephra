import SwiftUI
import ZephraCore
import ZephraEngine

/// Live GPU memory: what is held by live arrays, what the allocator is keeping for reuse, the
/// high-water mark since launch, which way the VAE decode is set to run — the one setting
/// that moves that high-water mark — and, when the weights are streamed, what the last pass
/// read and how fast. Polled once a second, and only while this tab is on screen.
struct MemoryReadout: View {
    @Environment(\.inferenceRuntime) private var runtime
    @Environment(GenerationStore.self) private var store
    @State private var snapshot: MemorySnapshot?
    @State private var streamed: WeightStreamReading?

    var body: some View {
        Group {
            if let snapshot {
                row("Active", snapshot.activeBytes)
                row("Cached", snapshot.cacheBytes)
                row("Peak since launch", snapshot.peakBytes)
                // The policy's answer for the chosen model, which is what the next run will
                // decode at; the runtime's own reading would say what the last run used.
                LabeledContent("VAE decode") {
                    Text(store.vaeTilingPolicy.tileSize(for: store.descriptor) != nil
                        ? "Tiled" : "Whole image")
                }
                if let streamed {
                    LabeledContent("Weights") {
                        Text(streamedText(streamed))
                            .monospacedDigit()
                    }
                }
            } else {
                Text("No inference runtime in this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: runtime == nil) { await poll() }
    }

    private func row(_ label: String, _ bytes: Int) -> some View {
        LabeledContent(label) {
            Text(bytes.formatted(.byteCount(style: .memory, spellsOutZero: false)))
                .monospacedDigit()
        }
    }

    /// "Streamed, 16.1 GB per pass at 1.6 GB/s".
    private func streamedText(_ reading: WeightStreamReading) -> String {
        String(
            format: "Streamed, %.1f GB per pass at %.1f GB/s",
            Double(reading.bytes) / 1_000_000_000, reading.bytesPerSecond / 1_000_000_000)
    }

    /// Reads the runtime until the tab goes away. `.task` is cancelled on disappear, so a
    /// hidden Performance tab costs nothing.
    private func poll() async {
        guard let runtime else { return }
        while !Task.isCancelled {
            snapshot = runtime.memorySnapshot()
            streamed = runtime.weightStreamReading()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

#Preview("Memory") {
    Form { Section("In use now") { MemoryReadout() } }
        .formStyle(.grouped)
        .frame(width: 480)
        .environment(GenerationStore.preview(state: .ready))
}

import SwiftUI
import ZephraCore
import ZephraEngine

/// Live GPU memory: what is held by live arrays, what the allocator is keeping for reuse, the
/// high-water mark since launch, which way the VAE decode is set to run — the one setting
/// that moves that high-water mark — and, when the weights are streamed, what the last pass
/// read and how fast.
///
/// Polled once a second, and only while this tab is the selected one: `MemoryReadoutPoll` is
/// the loop and the readings both, and `.task` here is what starts and cancels it. See the
/// note there for why a tab's `.task` really is that scope on macOS.
struct MemoryReadout: View {
    @Environment(\.inferenceRuntime) private var runtime
    @Environment(GenerationStore.self) private var store
    @State private var poll = MemoryReadoutPoll()

    var body: some View {
        Group {
            if let snapshot = poll.snapshot {
                row("Active", snapshot.activeBytes)
                row("Cached", snapshot.cacheBytes)
                row("Peak since launch", snapshot.peakBytes)
                // The policy's answer for the chosen model, which is what the next run will
                // decode at; the runtime's own reading would say what the last run used.
                LabeledContent("VAE decode") {
                    Text(store.vaeTilingPolicy.tileSize(for: store.descriptor) != nil
                        ? "Tiled" : "Whole image")
                }
                if let streamed = poll.streamed {
                    LabeledContent("Weights") {
                        Text(Self.streamedText(streamed))
                            .monospacedDigit()
                    }
                }
            } else {
                Text("No inference runtime in this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: runtime == nil) { await poll.run(reading: runtime) }
    }

    private func row(_ label: String, _ bytes: Int) -> some View {
        LabeledContent(label) {
            Text(bytes.formatted(.byteCount(style: .memory, spellsOutZero: false)))
                .monospacedDigit()
        }
    }

    /// "Streamed, 16.1 GB per pass at 1.6 GB/s".
    static func streamedText(_ reading: WeightStreamReading) -> String {
        String(
            format: "Streamed, %.1f GB per pass at %.1f GB/s",
            Double(reading.bytes) / 1_000_000_000, reading.bytesPerSecond / 1_000_000_000)
    }
}

#Preview("Memory") {
    Form { Section("In use now") { MemoryReadout() } }
        .formStyle(.grouped)
        .frame(width: 480)
        .environment(GenerationStore.preview(state: .ready))
}

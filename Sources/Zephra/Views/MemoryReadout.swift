import SwiftUI
import ZephraCore

/// Live GPU memory: what is held by live arrays, what the allocator is keeping for reuse, and
/// the high-water mark since launch. Polled once a second, and only while this tab is on screen.
struct MemoryReadout: View {
    @Environment(\.inferenceRuntime) private var runtime
    @State private var snapshot: MemorySnapshot?

    var body: some View {
        Group {
            if let snapshot {
                row("Active", snapshot.activeBytes)
                row("Cached", snapshot.cacheBytes)
                row("Peak since launch", snapshot.peakBytes)
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

    /// Reads the runtime until the tab goes away. `.task` is cancelled on disappear, so a
    /// hidden Performance tab costs nothing.
    private func poll() async {
        guard let runtime else { return }
        while !Task.isCancelled {
            snapshot = runtime.memorySnapshot()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

#Preview("Memory") {
    Form { Section("In use now") { MemoryReadout() } }
        .formStyle(.grouped)
        .frame(width: 480)
}

import SwiftUI
import ZephraEngine

/// The line under the list in Settings > Models: what everything adds up to, and whether the
/// figure is still being counted.
struct ModelStorageTotal: View {
    @Environment(ModelInventory.self) private var inventory

    var body: some View {
        HStack {
            Text(inventory.isMeasuring ? "Measuring…" : "Total")
            Spacer()
            Text(inventory.totalBytes.formatted(.byteCount(style: .file)))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

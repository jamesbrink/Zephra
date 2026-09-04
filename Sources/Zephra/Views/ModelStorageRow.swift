import AppKit
import SwiftUI
import ZephraSnapshot

/// One directory in Settings > Models: what it is, what it occupies, and a button to trash it.
struct ModelStorageRow: View {
    let item: ModelStorageItem
    /// True while the engine holds weights from this directory, which greys the button out.
    let inUse: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(size)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Delete", action: onDelete)
                .disabled(inUse)
                .help(inUse ? "In use. Choose another model first." : "Move it to the Trash")
        }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        }
    }

    private var caption: String {
        switch item.kind {
        case .download where !item.isComplete:
            "Partial download. Choosing the model resumes it."
        case .download where item.modelIDs.count > 1:
            "Downloaded. \(item.modelIDs.count) variants are built from it."
        case .download:
            "Downloaded"
        case .built:
            "Built on this Mac"
        }
    }

    private var size: String {
        item.bytes.map { $0.formatted(.byteCount(style: .file)) } ?? "Measuring…"
    }
}

#Preview("Row") {
    Form {
        ModelStorageRow(
            item: ModelStorageItem(
                name: "FLUX.2 klein 4B release", kind: .download,
                url: URL(filePath: "/tmp/klein"), modelIDs: ["a", "b"], isComplete: true,
                bytes: 16_000_000_000),
            inUse: false
        ) {}
        ModelStorageRow(
            item: ModelStorageItem(
                name: "Z-Image Turbo · 8-bit", kind: .download,
                url: URL(filePath: "/tmp/z"), modelIDs: ["z"], isComplete: false),
            inUse: true
        ) {}
    }
    .formStyle(.grouped)
    .frame(width: 480)
}

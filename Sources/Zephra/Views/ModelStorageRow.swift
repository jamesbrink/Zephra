import AppKit
import SwiftUI
import ZephraSnapshot

/// One directory in Settings > Models: what it is, what it occupies, and a button to permanently delete it.
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
                .help(inUse ? "In use. Choose another model first." : "Permanently delete these model files")
        }
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        }
    }

    /// What it is and where it is: the second half is what tells two copies of one release
    /// apart, which is otherwise two identical rows.
    private var caption: String {
        item.location.isEmpty ? state : "\(state) · \(item.location)"
    }

    /// A partial download is promised a resumption only where one can happen: the app's own
    /// folder is written to, the hub cache is only ever read (see `ModelStorageItem.Origin`).
    private var state: String {
        switch item.kind {
        case .download where !item.isComplete && item.origin == .hubCache:
            "Partial download left by hf; Zephra reads this cache and never writes it"
        case .download where !item.isComplete:
            "Partial download, resumed when the model is chosen"
        case .download where item.modelIDs.count > 1:
            "Downloaded, \(item.modelIDs.count) variants pack from it"
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
                url: URL(filePath: "/tmp/klein"),
                location: "Downloads/black-forest-labs--FLUX.2-klein-4B",
                modelIDs: ["a", "b"], isComplete: true, bytes: 16_000_000_000),
            inUse: false
        ) {}
        ModelStorageRow(
            item: ModelStorageItem(
                name: "Z-Image Turbo · 8-bit", kind: .download,
                url: URL(filePath: "/tmp/z"), location: "Downloads/mzbac--Z-Image-Turbo-8bit",
                modelIDs: ["z"], isComplete: false),
            inUse: true
        ) {}
        ModelStorageRow(
            item: ModelStorageItem(
                name: "Z-Image Turbo · 8-bit", kind: .download,
                url: URL(filePath: "/tmp/hub"), location: "~/.cache/huggingface/hub/models/mzbac/Z-Image-Turbo-8bit",
                modelIDs: ["z"], isComplete: false, origin: .hubCache),
            inUse: false
        ) {}
    }
    .formStyle(.grouped)
    .frame(width: 480)
}

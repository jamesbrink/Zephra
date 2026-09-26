import SwiftUI
import ZephraLinkProtocol

struct RemoteModelStorageRow: View {
    let item: ModelStorageDTO
    let host: HostConnection
    let storage: RemoteModelStorage
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.bytes?.formatted(.byteCount(style: .file)) ?? "Size unavailable").font(.caption).monospacedDigit()
            if item.inUse { Text("In use · Unload and finish queued jobs first").font(.caption).foregroundStyle(.secondary) }
            Button("Delete Files", systemImage: "trash", role: .destructive) { storage.deleting = item }
                .disabled(item.inUse || storage.loading || !host.client.connection.isLive)
        }
    }
}

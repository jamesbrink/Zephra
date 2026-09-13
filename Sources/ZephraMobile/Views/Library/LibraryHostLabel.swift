import SwiftUI

struct LibraryHostLabel: View {
    let entry: CachedEntry
    @Environment(HostConnections.self) private var hosts
    var body: some View {
        if let host = hosts.hosts.first(where: { $0.id == entry.hostID }) {
            Text(host.name + (host.client.connection.isLive ? "" : " · Offline"))
                .font(.caption2)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .foregroundStyle(.white)
                .background(.black.opacity(0.65), in: Capsule())
                .accessibilityLabel("Source: \(host.name)\(host.client.connection.isLive ? "" : ", offline")")
        }
    }
}

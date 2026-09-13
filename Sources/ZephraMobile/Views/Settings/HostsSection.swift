import SwiftUI

struct HostsSection: View {
    @Environment(HostConnections.self) private var hosts
    var body: some View {
        Section("Your Macs") {
            ForEach(hosts.hosts) { host in
                NavigationLink { HostDetail(host: host) } label: {
                    VStack(alignment: .leading) {
                        Text(host.name)
                        Text(host.client.connection.isLive ? "Connected" : "Offline")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button("Add Mac", systemImage: "plus") { hosts.isAdding = true }
            if let failure = hosts.failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }
    }
}

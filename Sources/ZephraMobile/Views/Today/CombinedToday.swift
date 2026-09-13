import SwiftUI

struct CombinedToday: View {
    @Environment(HostConnections.self) private var hosts
    @Environment(GenerationDispatch.self) private var dispatch
    var body: some View {
        NavigationStack {
            List {
                ForEach(hosts.hosts) { host in
                    Section {
                        HostTodayRows(host: host)
                            .environment(host.client)
                            .environment(host.catalog)
                    } header: {
                        Button { hosts.watch(host.id) } label: {
                            Text(host.name + (host.client.connection.isLive ? "" : " · Offline"))
                        }
                    }
                }
                Section("Submissions") {
                    ForEach(dispatch.submissions.reversed()) { submission in
                        VStack(alignment: .leading) {
                            Text(submission.hostName)
                            Text(submission.state == .unknown ? "Checking submission · may already be running" : submission.state.rawValue.capitalized)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Today")
        }
    }
}

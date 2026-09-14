import SwiftUI

struct CombinedToday: View {
    @Environment(HostConnections.self) private var hosts
    @Environment(GenerationDispatch.self) private var dispatch
    @State private var viewing: ViewerOpening?
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
        // Present once from the screen, never from the transparent group of list rows.
        // A cover on that group fans out to multiple presenters and crashes UIKit's zoom.
        .modifier(LibraryRequests())
        .modifier(ViewerCover(opening: $viewing) { opening in
            TodayPictures.entries(around: opening.opened, hosts: hosts.hosts)
        })
    }
}

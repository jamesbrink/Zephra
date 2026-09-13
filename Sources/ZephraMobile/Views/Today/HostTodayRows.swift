import SwiftUI
import ZephraLinkProtocol

struct HostTodayRows: View {
    let host: HostConnection
    @State private var viewing: ViewerOpening?
    var body: some View {
        Group {
            ForEach(host.client.snapshot?.today ?? []) { run in
                switch run.state {
                case .running:
                    RunningRunCard(run: run)
                    WatchHostButton(host: host)
                case .waiting: WaitingRunCard(run: run)
                case .finished: FinishedRunRow(run: run)
                }
            }
        }
        .modifier(LibraryRequests())
        .modifier(ViewerCover(opening: $viewing) { _ in host.catalog.entries })
    }
}

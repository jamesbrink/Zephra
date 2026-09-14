import SwiftUI
import ZephraLinkProtocol

struct HostTodayRows: View {
    let host: HostConnection
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
    }
}

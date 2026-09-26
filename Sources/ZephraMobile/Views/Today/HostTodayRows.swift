import SwiftUI
import ZephraLinkProtocol

struct HostTodayRows: View {
    let host: HostConnection
    var body: some View {
        Group {
            let runs = host.client.snapshot?.today ?? []
            if runs.isEmpty { Text("No generations today").font(.callout).foregroundStyle(.secondary) }
            ForEach(runs) { run in
                switch run.state {
                case .running:
                    RunningRunCard(run: run)
                    WatchHostButton(host: host)
                case .waiting: WaitingRunCard(run: run).modifier(QueueRunActions(id: run.id))
                case .finished: FinishedRunRow(run: run)
                }
            }
        }
    }
}

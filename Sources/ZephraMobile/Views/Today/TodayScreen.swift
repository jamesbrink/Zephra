import SwiftUI
import ZephraLinkClient
import ZephraLinkProtocol
import ZephraStyle

/// Today's runs, as the Mac's own canvas sidebar groups them.
///
/// Top to bottom it reads future, present, past — the Mac's order: what is waiting, what is
/// being rendered, and under those what has come out. Nothing here groups anything.
/// `RunSummary` arrives already grouped, because the grouping is a rule about a press of
/// Generate and the Mac is what pressed it.
///
/// This surface is the one place on the phone that is about *now*, so it is the one that goes
/// blank without a Mac: a run in flight cannot be cached.
struct TodayScreen: View {
    @Environment(LinkClient.self) private var client
    /// The picture from a finished run that is open full size, or nil.
    @State private var viewing: CachedEntry?

    var body: some View {
        NavigationStack {
            List {
                if runs.isEmpty {
                    Text("Nothing made today yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(runs) { run in
                        row(run)
                            .listRowSeparator(.hidden)
                            .listRowInsets(
                                EdgeInsets(top: 4, leading: MobileChrome.sideMargin, bottom: 4,
                                    trailing: MobileChrome.sideMargin))
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(MobileTab.today.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        // A picture in a run's strip opens the same way it does in the library, and wears the
        // same menu: the actions are the library's and this surface keeps no copy of them.
        .environment(\.openLibraryItem) { viewing = $0 }
        .modifier(LibraryRequests())
        .fullScreenCover(item: $viewing) { entry in
            LibraryViewer(entries: [entry], opening: entry.fileName)
        }
    }

    /// The row one run gets, which is decided by where the run stands.
    @ViewBuilder private func row(_ run: RunSummary) -> some View {
        switch run.state {
        case .running: RunningRunCard(run: run)
        case .waiting: WaitingRunCard(run: run)
        case .finished: FinishedRunRow(run: run)
        }
    }

    /// Today's runs as the Mac lists them.
    private var runs: [RunSummary] { client.snapshot?.today ?? [] }
}

#Preview("Today") {
    TodayScreen()
        .environment(MobilePreview.client() ?? MobilePreview.unpairedClient())
        .environment(LibraryCatalog(libraryRoot: nil, filesRoot: nil))
}

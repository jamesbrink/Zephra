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
    @Environment(LibraryCatalog.self) private var catalog
    /// The picture from a finished run that is open full size, and the one the viewer has
    /// paged to, or nil.
    @State private var viewing: ViewerOpening?

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
        // A picture in a run's strip opens the same way it does in the library, zooms out of
        // its cell the same way, and wears the same menu: the actions are the library's and
        // this surface keeps no copy of them.
        .modifier(LibraryRequests())
        .modifier(ViewerCover(opening: $viewing) { pictures(around: $0.opened) })
    }

    /// The pictures the viewer pages through: the run's, in the strip's order, so a swipe
    /// walks the seeds of one press of Generate and stops at its end.
    private func pictures(around entry: CachedEntry) -> [CachedEntry] {
        guard let run = runs.first(where: { $0.fileNames.contains(entry.fileName) }) else {
            return [entry]
        }
        return run.fileNames.compactMap(catalog.entry(named:))
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
        .environment(PromptDraft())
        .environment(ReferenceIntent())
        .environment(MobileSelection())
}

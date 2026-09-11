import SwiftUI
import ZephraLinkClient

/// Today's runs, as the Mac's own canvas sidebar groups them. A placeholder for now: the wall
/// of squares and the run cards come next.
struct TodayScreen: View {
    @Environment(LinkClient.self) private var client

    var body: some View {
        SurfacePlaceholder(
            title: MobileTab.today.title, symbol: MobileTab.today.symbol, fact: fact)
    }

    /// How many runs the Mac has made today, and how many pictures are in them. The grouping
    /// is the Mac's: `today` arrives already grouped, and nothing here filters.
    private var fact: String? {
        guard let today = client.snapshot?.today else { return nil }
        guard !today.isEmpty else { return "No runs yet today." }
        let pictures = today.reduce(0) { $0 + $1.seedCount }
        return "\(today.count) \(today.count == 1 ? "run" : "runs") today, \(pictures) in all"
    }
}

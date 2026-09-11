import SwiftUI

/// The Mac's library. A placeholder for now: the grid, its scopes and the viewer come next.
struct LibraryScreen: View {
    @Environment(MobileSession.self) private var session

    var body: some View {
        SurfacePlaceholder(
            title: MobileTab.library.title, symbol: MobileTab.library.symbol, fact: fact)
    }

    /// How much of the library the phone is holding, out of what the Mac says it has. The two
    /// differ on purpose: the library arrives a page at a time.
    private var fact: String? {
        guard let total = session.snapshot?.libraryCount else { return nil }
        guard total > 0 else { return "Nothing in the library yet." }
        let held = session.library.count
        return held < total
            ? "\(held) of \(total) pictures"
            : "\(total) \(total == 1 ? "picture" : "pictures")"
    }
}

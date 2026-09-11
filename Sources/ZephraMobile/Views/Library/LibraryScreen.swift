import SwiftUI
import ZephraStyle

/// The Mac's library, on the phone.
///
/// Everything on it came over the link and is kept here, so this surface works with no Mac in
/// reach: the grid, the search, the scopes and every picture already looked at are all drawn
/// from `LibraryCatalog`. What needs the Mac — favoriting, tagging, deleting, and fetching
/// something never fetched — shows greyed instead of failing when it is pressed.
///
/// Nothing here filters. The chips and the search field write the catalog's query and the
/// catalog answers with sections, which is the Mac's rule and the Mac's reason: "which
/// pictures belong on screen" is a question with a test, not a line in a view.
struct LibraryScreen: View {
    @Environment(LibraryCatalog.self) private var catalog
    /// The day whose pictures are open full size, and which of them, or nil for the grid.
    @State private var viewing: CachedEntry?

    var body: some View {
        @Bindable var catalog = catalog
        NavigationStack {
            VStack(spacing: 0) {
                ScopeChips()
                LibraryGrid()
            }
            .background(Color.canvasBackground)
            .navigationTitle(MobileTab.library.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $catalog.query.text, prompt: "Search prompts and tags")
        }
        .environment(\.openLibraryItem) { viewing = $0 }
        .modifier(LibraryRequests())
        .fullScreenCover(item: $viewing) { entry in
            LibraryViewer(entries: wall, opening: entry.fileName)
        }
        // Keyed on the count, because the catalog reads the disk and then the client before it
        // has anything: a plain `.task` runs while the grid is still empty.
        .task(id: catalog.entries.count) { openFirstIfPhotographing() }
    }

    /// The pictures the viewer pages through: the whole grid, in the grid's order.
    ///
    /// The whole grid rather than the opened picture's day, because the grid is one continuous
    /// wall and the day headers are labels on it, not walls of their own: a swipe that stopped
    /// at midnight stopped at a place nobody could see from the picture they were looking at.
    /// Photos pages the whole camera roll for the same reason, and the viewer is lazy enough
    /// that a library of thousands costs the same as a day.
    private var wall: [CachedEntry] {
        catalog.sections.flatMap(\.entries)
    }

    /// The `viewer` preview state is the library with its first picture open, so a screenshot
    /// of the viewer is taken the same way as a screenshot of anything else.
    private func openFirstIfPhotographing() {
        guard MobilePreview.opensViewer, viewing == nil else { return }
        viewing = catalog.sections.first?.entries.first
    }
}

#Preview("Library") {
    LibraryScreen()
        .environment(MobilePreview.client() ?? MobilePreview.unpairedClient())
        .environment(LibraryCatalog(libraryRoot: nil, filesRoot: nil))
        .environment(ReferenceIntent())
        .environment(MobileSelection())
}

import SwiftUI

/// The wall of pictures, grouped by the day they were made.
///
/// Density comes from the pinch gesture or Thumbnail Size menu. The headings stay pinned.
///
/// Nothing here filters or sorts. `LibraryCatalog.sections` is the answer and this draws it.
///
/// While the viewer is up, the grid follows it: each picture it pages to has its cell
/// scrolled into view, unanimated, behind a cover that is opaque at rest — so when the viewer
/// closes, the cell it zooms back into is on screen to be zoomed into.
struct LibraryGrid: View {
    @Environment(LibraryCatalog.self) private var catalog
    /// What a tap on a picture means, which is the surface's business and not a cell's.
    @Environment(\.galleryColumns) private var columns
    /// Which picture the viewer over this grid is showing, if one is up.
    @Environment(\.viewerOpening) private var opening

    /// The gap between two cells, and between a day's last row and the next day's heading.
    private static let cellSpacing: CGFloat = 3
    private static let sectionSpacing: CGFloat = 14

    var body: some View {
        ScrollViewReader { wall in
            GalleryScroll {
                if catalog.sections.isEmpty {
                    LibraryEmptyState()
                        .frame(maxWidth: .infinity, minHeight: 340)
                } else {
                    grid
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: opening?.shown) { _, shown in
                if let shown { wall.scrollTo(shown, anchor: .center) }
            }
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Self.cellSpacing), count: columns),
            spacing: Self.cellSpacing,
            pinnedViews: [.sectionHeaders]
        ) {
            ForEach(catalog.sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        LibraryOpeningCell(entry: entry)
                    }
                } header: {
                    LibraryDayHeader(section: section)
                }
            }
        }
        .scrollTargetLayout()
        .padding(.horizontal, Self.cellSpacing)
        .padding(.bottom, MobileChrome.tabBarInset)
    }
}

#Preview("Grid") {
    LibraryGrid()
        .environment(LibraryCatalog(libraryRoot: nil, filesRoot: nil))
}

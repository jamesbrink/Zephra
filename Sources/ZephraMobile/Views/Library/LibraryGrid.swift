import SwiftUI

/// The wall of pictures, grouped by the day they were made.
///
/// Three across, and three whatever the phone is: a fourth column on a Pro Max would make the
/// pictures smaller on the larger screen, which is backwards. The headings are pinned, so the
/// day scrolls up and stays legible over its own pictures.
///
/// Nothing here filters or sorts. `LibraryCatalog.sections` is the answer and this draws it.
struct LibraryGrid: View {
    @Environment(LibraryCatalog.self) private var catalog
    /// What a tap on a picture means, which is the surface's business and not a cell's.
    @Environment(\.openLibraryItem) private var open

    /// The gap between two cells, and between a day's last row and the next day's heading.
    private static let cellSpacing: CGFloat = 3
    private static let sectionSpacing: CGFloat = 14

    var body: some View {
        ScrollView {
            if catalog.sections.isEmpty {
                LibraryEmptyState()
                    .frame(maxWidth: .infinity, minHeight: 340)
            } else {
                grid
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Self.cellSpacing), count: 3),
            spacing: Self.cellSpacing,
            pinnedViews: [.sectionHeaders]
        ) {
            ForEach(catalog.sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        LibraryCell(entry: entry)
                            .onTapGesture { open(entry) }
                    }
                } header: {
                    LibraryDayHeader(section: section)
                }
            }
        }
        .padding(.horizontal, Self.cellSpacing)
        .padding(.bottom, MobileChrome.tabBarInset)
    }
}

#Preview("Grid") {
    LibraryGrid()
        .environment(LibraryCatalog(libraryRoot: nil, filesRoot: nil))
}

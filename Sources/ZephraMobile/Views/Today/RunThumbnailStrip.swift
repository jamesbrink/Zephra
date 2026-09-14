import SwiftUI
import ZephraStyle

/// One run's pictures in a row, small.
///
/// A strip rather than a grid: a run is two or four seeds, and the point of showing them here
/// is to recognise the run, not to look at any one of them. Tapping one opens it the way the
/// grid does, through the same `\.openLibraryItem` the library fills in — the Today surface
/// has no viewer of its own to keep in step.
struct RunThumbnailStrip: View {
    /// The pictures the run made, oldest first, as file names.
    let fileNames: [String]

    @Environment(LibraryCatalog.self) private var catalog
    /// Which picture the viewer over this strip is showing, if one is up: its cell is kept on
    /// screen, the way the library's grid keeps it, so the viewer has a cell to zoom back into.
    @Environment(\.viewerOpening) private var opening

    /// How big one is: about a fifth of a phone's width, so four fit with room to spare.
    private static let edge: CGFloat = 72

    var body: some View {
        ScrollViewReader { strip in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(fileNames, id: \.self) { name in
                        if let entry = catalog.entry(named: name) {
                            RunThumbnail(entry: entry)
                                .frame(width: Self.edge, height: Self.edge)
                                .id(entry.id)
                        } else {
                            RoundedRectangle(
                                cornerRadius: ZephraChrome.tileRadius, style: .continuous
                            )
                            .fill(.quaternary)
                            .frame(width: Self.edge, height: Self.edge)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: opening?.shown) { _, shown in
                if let shown, fileNames.contains(where: { catalog.entry(named: $0)?.id == shown }) {
                    strip.scrollTo(shown)
                }
            }
        }
    }
}

/// One picture in a run's strip.
///
/// Its own view so the thumbnail it is waiting for is its own state: a strip that held four
/// of them would redraw all four every time one arrived.
private struct RunThumbnail: View {
    let entry: CachedEntry

    @Environment(\.openLibraryItem) private var open

    var body: some View {
        LibraryCell(entry: entry)
            .onTapGesture { open(entry) }
    }
}

import SwiftUI
import ZephraEngine
import ZephraStyle

/// One of the collections that is always there: all images, favourites, the last seven days.
///
/// The count comes from `LibraryCounts`, which is worked out once per scan over every item, so
/// a sidebar of a dozen of these is one pass rather than a dozen filters.
struct LibrarySourceRow: View {
    /// Which collection the row stands for.
    let scope: LibraryScope

    @Environment(LibraryIndex.self) private var index

    var body: some View {
        HStack(spacing: 8) {
            Label(scope.title, systemImage: scope.systemImage)
                .lineLimit(1)
            Spacer(minLength: 8)
            CountBadge(index.counts.count(for: scope))
        }
        .frame(height: ZephraChrome.sidebarRowHeight)
        .tag(scope)
    }
}

#Preview("Standing sources") {
    List {
        LibrarySourceRow(scope: .all)
        LibrarySourceRow(scope: .favourites)
        LibrarySourceRow(scope: .lastSevenDays)
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 140)
    .environment(PreviewImages.library(count: 38))
}

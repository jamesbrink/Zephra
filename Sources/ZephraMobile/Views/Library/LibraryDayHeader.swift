import SwiftUI
import ZephraStyle

/// The line above one day's pictures: which day, and how many.
///
/// The Mac's `LibraryDayHeader`, down to the word after the count following the scope: under
/// Favorites, six pictures is six favorites, and calling them pictures there would be counting
/// something that is not on screen.
///
/// It has a ground of its own because it is pinned: without one the pictures scroll under the
/// text and neither can be read.
struct LibraryDayHeader: View {
    /// The day this header stands over.
    let section: CachedSection

    @Environment(LibraryCatalog.self) private var catalog

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(section.title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MobileChrome.sideMargin - 3)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var detail: String {
        let count = section.entries.count
        return "\(count) \(catalog.query.scope.noun(count))"
    }
}

#Preview("Day") {
    LibraryDayHeader(section: CachedSection(day: Date(), entries: []))
        .environment(LibraryCatalog(libraryRoot: nil, filesRoot: nil))
}

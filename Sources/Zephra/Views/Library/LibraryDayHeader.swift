import SwiftUI
import ZephraEngine

/// The line above one day's images: which day, and how many.
///
/// "Today" and "Yesterday" rather than the date, for the two days a person is most likely to be
/// looking for; everything older is named, and a day in another year says which year.
///
/// The word after the count follows the scope, because the grid is not always showing all of
/// them: under Favourites, six images is six favourites, and saying "6 images" there would be
/// counting something that is not on screen.
struct LibraryDayHeader: View {
    /// The day this header stands over.
    let section: LibrarySection

    @Environment(LibraryIndex.self) private var index

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(section.day) { return "Today" }
        if calendar.isDateInYesterday(section.day) { return "Yesterday" }
        let sameYear = calendar.isDate(section.day, equalTo: Date(), toGranularity: .year)
        return section.day.formatted(
            sameYear ? .dateTime.day().month(.wide) : .dateTime.day().month(.wide).year()
        )
    }

    private var detail: String {
        let count = section.items.count
        let noun = index.query.scope == .favourites
            ? (count == 1 ? "favourite" : "favourites")
            : (count == 1 ? "image" : "images")
        return "\(count) \(noun)"
    }
}

#Preview("Day headers") {
    let index = LibraryIndex.preview(count: 12)
    return VStack(alignment: .leading, spacing: 20) {
        ForEach(index.sections) { section in
            LibraryDayHeader(section: section)
        }
    }
    .padding(24)
    .frame(width: 420)
    .environment(index)
}

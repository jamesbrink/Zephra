import Foundation

/// One day's pictures, which is the unit the phone's grid is built out of.
///
/// The Mac's `LibrarySection` in the phone's terms, down to the identity being the day itself:
/// a day is what somebody remembers working on, and it gives a heading that means something
/// with no state behind it.
nonisolated struct CachedSection: Identifiable, Hashable, Sendable {
    /// The start of the local day, which is also the section's identity.
    var id: Date { day }
    /// The day these pictures belong to.
    let day: Date
    /// The pictures made that day, newest first.
    let entries: [CachedEntry]

    /// Groups one day's pictures.
    init(day: Date, entries: [CachedEntry]) {
        self.day = day
        self.entries = entries
    }

    /// What the heading says: "Today" and "Yesterday" for the two days somebody is most likely
    /// to be looking for, the date otherwise, and the year too once it is not this one.
    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let thisYear = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
        return day.formatted(
            thisYear ? .dateTime.day().month(.wide) : .dateTime.day().month(.wide).year())
    }
}

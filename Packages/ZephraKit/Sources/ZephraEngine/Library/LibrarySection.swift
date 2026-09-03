import Foundation

/// One day's images, which is the unit the library grid is built out of.
///
/// The day rather than an arbitrary page: a day is what a person remembers working on, and it
/// gives the grid a heading that means something without any state behind it.
public struct LibrarySection: Identifiable, Hashable, Sendable {
    /// The start of the local day, which is also the section's identity.
    public var id: Date { day }
    /// The start of the local day these images belong to.
    public let day: Date
    /// The images made that day, in the query's order.
    public let items: [LibraryItem]

    /// Groups one day's images.
    public init(day: Date, items: [LibraryItem]) {
        self.day = day
        self.items = items
    }
}

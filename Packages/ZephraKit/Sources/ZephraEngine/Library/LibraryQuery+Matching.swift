import Foundation

/// Turning a query into the images it names.
///
/// Pure functions over items the caller already holds, so the same query answers the grid, the
/// filter bar's count, and the sidebar's "how many would this show" without any of them owning
/// anything. Matching is a substring test against a key that was folded when the item was read,
/// which is what keeps typing in the search box cheap.
extension LibraryQuery {
    /// Whether one image belongs in this query's results.
    ///
    /// The scope decides which collection is being looked at, so an image in Recently Deleted
    /// never shows up under a model or a tag: it is not in the library until it is restored.
    /// `now` decides where the last seven days start, and is a parameter only so a test can
    /// pin it.
    public func matches(_ item: LibraryItem, now: Date = Date()) -> Bool {
        guard matchesScope(item, now: now) else { return false }
        if let modelID, item.modelID != modelID { return false }
        if let tag, !item.tags.contains(tag) { return false }
        let text = trimmedText
        guard !text.isEmpty else { return true }
        return item.searchKey.contains(LibraryItem.folded(text))
    }

    /// The images this query names, in its own order.
    public func matching(_ items: [LibraryItem], now: Date = Date()) -> [LibraryItem] {
        let found = items.filter { matches($0, now: now) }
        return found.sorted { first, second in
            first.createdAt == second.createdAt
                ? first.id < second.id
                : (sort == .newestFirst
                    ? first.createdAt > second.createdAt
                    : first.createdAt < second.createdAt)
        }
    }

    /// The images this query names, grouped into the days the grid shows them under.
    ///
    /// Days run in the same direction as the images inside them, so oldest-first reads top to
    /// bottom the way the images were made.
    public func sections(of items: [LibraryItem], now: Date = Date()) -> [LibrarySection] {
        var order: [Date] = []
        var byDay: [Date: [LibraryItem]] = [:]
        for item in matching(items, now: now) {
            if byDay[item.day] == nil { order.append(item.day) }
            byDay[item.day, default: []].append(item)
        }
        return order.map { LibrarySection(day: $0, items: byDay[$0] ?? []) }
    }

    private func matchesScope(_ item: LibraryItem, now: Date) -> Bool {
        switch scope {
        case .all:
            item.collection == .generated
        case .favourites:
            item.collection == .generated && item.isFavourite
        case .lastSevenDays:
            item.collection == .generated
                && item.createdAt >= now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .album(let id):
            item.collection == .generated && item.annotation.albums.contains { $0.id == id }
        case .recentlyDeleted:
            item.collection == .recentlyDeleted
        case .sources:
            item.collection == .sources
        }
    }
}

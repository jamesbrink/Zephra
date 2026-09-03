import Foundation

/// The numbers beside the sidebar's rows, worked out in one pass over the items.
///
/// A pure function of the items and the albums that exist, not state: there is nothing to keep
/// in step, and a count can never disagree with the grid it is describing. One pass rather than
/// a filter per row, because the sidebar shows a dozen of these at once.
public struct LibraryCounts: Hashable, Sendable {
    /// Every generated image that has not been deleted.
    public let total: Int
    /// How many of those are favourites.
    public let favourites: Int
    /// How many were made in the last seven days.
    public let lastSevenDays: Int
    /// How many are waiting in Recently Deleted.
    public let recentlyDeleted: Int
    /// How many imported pictures there are.
    public let sources: Int
    /// Generated images per model, by descriptor identifier.
    public let perModel: [String: Int]
    /// Generated images per tag.
    public let perTag: [String: Int]
    /// Generated images per album. Albums that exist and hold nothing are present, at zero.
    public let perAlbum: [UUID: Int]

    /// Nothing counted yet, which is what an index shows before its first scan.
    public static let empty = LibraryCounts(items: [])

    /// Counts `items`, seeding the album counts with `albumIDs` so an empty album still has a
    /// row to show. `now` decides where the last seven days start, and is a parameter only so
    /// a test can pin it.
    public init(items: [LibraryItem], albumIDs: [UUID] = [], now: Date = Date()) {
        var total = 0
        var favourites = 0
        var recent = 0
        var deleted = 0
        var sources = 0
        var perModel: [String: Int] = [:]
        var perTag: [String: Int] = [:]
        var perAlbum = Dictionary(uniqueKeysWithValues: albumIDs.map { ($0, 0) })
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        for item in items {
            switch item.collection {
            case .recentlyDeleted: deleted += 1
            case .sources: sources += 1
            case .generated:
                total += 1
                if item.isFavourite { favourites += 1 }
                if item.createdAt >= cutoff { recent += 1 }
                if let model = item.modelID { perModel[model, default: 0] += 1 }
                for tag in item.tags { perTag[tag, default: 0] += 1 }
                for album in item.annotation.albums { perAlbum[album.id, default: 0] += 1 }
            }
        }
        self.total = total
        self.favourites = favourites
        self.lastSevenDays = recent
        self.recentlyDeleted = deleted
        self.sources = sources
        self.perModel = perModel
        self.perTag = perTag
        self.perAlbum = perAlbum
    }

    /// How many images one scope holds, which is the number its sidebar row shows.
    public func count(for scope: LibraryScope) -> Int {
        switch scope {
        case .all: total
        case .favourites: favourites
        case .lastSevenDays: lastSevenDays
        case .album(let id): perAlbum[id] ?? 0
        case .recentlyDeleted: recentlyDeleted
        case .sources: sources
        }
    }
}

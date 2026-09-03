import Foundation

/// Which collection of the library is being looked at.
///
/// The scope is what the sidebar selects and what the counts beside its rows are for. It is
/// deliberately separate from the filters in `LibraryQuery`: a model or a tag narrows whichever
/// scope is showing, whereas a scope decides which images exist at all.
public enum LibraryScope: Hashable, Sendable {
    /// Every generated image that has not been deleted.
    case all
    /// The images marked as favourites.
    case favourites
    /// Images made in the last seven days, by their own creation date.
    case lastSevenDays
    /// The members of one album.
    case album(UUID)
    /// Images that were deleted and are waiting to be purged or restored.
    case recentlyDeleted
    /// Imported pictures a generation can start from, kept apart from the images it makes.
    case sources
}

extension LibraryScope: RawRepresentable {
    /// A stable spelling for preferences: `all`, `favourites`, `album:<uuid>`, and so on.
    public var rawValue: String {
        switch self {
        case .all: "all"
        case .favourites: "favourites"
        case .lastSevenDays: "last-seven-days"
        case .album(let id): "album:\(id.uuidString)"
        case .recentlyDeleted: "recently-deleted"
        case .sources: "sources"
        }
    }

    /// Reads a scope back from its stable spelling; nil for anything unrecognised.
    public init?(rawValue: String) {
        switch rawValue {
        case "all": self = .all
        case "favourites": self = .favourites
        case "last-seven-days": self = .lastSevenDays
        case "recently-deleted": self = .recentlyDeleted
        case "sources": self = .sources
        default:
            guard rawValue.hasPrefix("album:"),
                  let id = UUID(uuidString: String(rawValue.dropFirst("album:".count)))
            else { return nil }
            self = .album(id)
        }
    }
}

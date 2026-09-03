import ZephraEngine

/// What each collection of the library is called on screen, and the symbol beside it.
///
/// In the app rather than in `ZephraEngine`, because a scope is a value and what it is called
/// is a matter of copy. The engine has no opinion about the word "Favourites".
extension LibraryScope {
    /// The row's title.
    var title: String {
        switch self {
        case .all: "All images"
        case .favourites: "Favourites"
        case .lastSevenDays: "Last 7 days"
        case .album: "Album"
        case .recentlyDeleted: "Recently deleted"
        case .sources: "Source images"
        }
    }

    /// The symbol before it.
    var systemImage: String {
        switch self {
        case .all: "photo.on.rectangle"
        case .favourites: "star"
        case .lastSevenDays: "clock"
        case .album: "rectangle.stack"
        case .recentlyDeleted: "trash"
        case .sources: "photo.badge.plus"
        }
    }
}
